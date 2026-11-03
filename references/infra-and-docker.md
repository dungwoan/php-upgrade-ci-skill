# Infrastructure, Docker, ini, .htaccess and CI for a PHP 8.x upgrade (Phase 3 and 7)

## Contents

1. Runtime choice: mod_php or php-fpm
2. Dockerfile skeleton for a CodeIgniter 3 app
3. Error visibility: one rule, every place
4. php.ini and the zz-custom.ini
5. .htaccess under PHP 8
6. CI_ENV and writers of .htaccess
7. Env files baked into the image
8. Extensions: install only with a caller
9. ext-mongodb version matching
10. Composer in the build
11. CI lint stage
12. Local checks without PHP on the host
13. Smoke environment
14. Things that go wrong here

## 1. Runtime choice: mod_php or php-fpm

| | mod_php (`php:<ver>-apache`) | php-fpm (nginx or Apache proxy) |
|---|---|---|
| `php_value`, `php_flag` in `.htaccess` | Valid | Cause HTTP 500 for the whole site |
| `php.ini` | Yes | Yes, plus pool configuration for per-pool values |
| Smallest change from the current setup | Yes | Needs web-server config as well |
| Used by the reference run | Yes (`php:8.4.27-apache`) | No |

Decide in Phase 0. Moving to php-fpm means moving every `php_value` and `php_flag` into `php.ini` or the pool, and checking that only `index.php` and the expected entry points run PHP (one project did this with nginx: other `.php` files return 404). Do not switch runtime and web server in the same change as the PHP bump unless the user asks for it.

## 2. Dockerfile skeleton for a CodeIgniter 3 app

This shows the shape the reference run used. Adjust the package list to the app. Replace placeholders.

```dockerfile
# Pin the exact PHP patch release your security process approves. Allow override at build time.
ARG PHP_VERSION=8.4.27
FROM php:${PHP_VERSION}-apache

ENV TZ=Etc/UTC
ENV DEBIAN_FRONTEND=noninteractive

# ext-mongodb: pick the version that supports both PHP and your MongoDB server (see section 9).
ARG MONGODB_EXT_VERSION=1.19.4

RUN apt-get update && apt-get install -y --no-install-recommends \
      git unzip curl libssl-dev pkg-config libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
      libzip-dev libicu-dev libmemcached-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Bundled extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd zip mysqli pdo_mysql bcmath sockets opcache intl

# Extensions that are not simple bundled builds (imap left core in 8.4). Pin the installer image tag.
COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/install-php-extensions
RUN chmod 0755 /usr/local/bin/install-php-extensions && install-php-extensions imap

# PECL extensions. Fetch the release tarball directly: pecl REST lookups time out in some builds.
ADD https://github.com/mongodb/mongo-php-driver/releases/download/${MONGODB_EXT_VERSION}/mongodb-${MONGODB_EXT_VERSION}.tgz /tmp/mongodb.tgz
RUN pecl install /tmp/mongodb.tgz && rm -f /tmp/mongodb.tgz && docker-php-ext-enable mongodb
RUN (printf "\n" | pecl install redis) && docker-php-ext-enable redis
RUN (printf "\n" | pecl install memcached) && docker-php-ext-enable memcached
# Add ftp or soap here only when code calls them (section 8).

# Apache: rewrite for CodeIgniter, .htaccess allowed
RUN a2enmod rewrite headers \
    && sed -ri '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
    && echo "ServerName localhost" >> /etc/apache2/apache2.conf \
    && echo "ServerTokens Prod" >> /etc/apache2/apache2.conf \
    && echo "ServerSignature Off" >> /etc/apache2/apache2.conf

# php.ini and the error policy (section 4)
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini \
    && { \
      echo 'upload_max_filesize = 20M'; \
      echo 'post_max_size = 20M'; \
      echo 'memory_limit = 512M'; \
      echo 'max_execution_time = 300'; \
      echo 'expose_php = Off'; \
      echo "date.timezone = ${TZ}"; \
      echo 'error_reporting = E_ALL'; \
      echo 'display_errors = Off'; \
      echo 'log_errors = On'; \
      echo 'error_log = /proc/self/fd/2'; \
    } > /usr/local/etc/php/conf.d/zz-custom.ini

WORKDIR /var/www/html
COPY . /var/www/html/

# Dependencies from the committed lock file (section 10)
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
RUN composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist \
    && composer clear-cache \
    && rm -f /usr/bin/composer

RUN chown -R www-data:www-data /var/www/html/
EXPOSE 80
```

Rules behind the skeleton:

- `FROM php:<exact-patch>-apache`. Tag names are not evidence of the runtime: run `php -v` in the built image.
- Copy the source last so that dependency layers cache well. Do not copy `.env` into the image unless you accept a rebuild for every value change (section 7).
- Remove build-only files from the webroot (`Dockerfile`, `.git`) or block them in `.htaccess` (section 5).
- `apt`, `pecl` and `ADD` fetch from the network at build time. That is normal for an image build; the CI scripts in this skill do not add network use.

### Cron inside the web container

The reference run starts cron by patching the Apache entrypoint (`sed` on `apache2-foreground`). It works, but it means two services share one container and one failure takes both down. Keep it if the user wants it, and record it as a risk. A separate cron container is the safer shape.

## 3. Error visibility: one rule, every place

Hidden deprecations are the most common reason an upgrade looks clean and fails later. Find every writer of error settings. Then set each one to the same policy.

| Place | What it sets | Production value | Local or dev value |
|---|---|---|---|
| Image ini (`zz-custom.ini`) | `error_reporting`, `display_errors`, `log_errors`, `error_log` | `E_ALL`, `Off`, `On`, `/proc/self/fd/2` | same |
| Front controller (`index.php`) | `error_reporting()` per `ENVIRONMENT` | `E_ALL` (no `~E_DEPRECATED`) | `E_ALL` |
| Env bootstrap (for example `Dotenv.php`) | `display_errors` when a debug flag is true | not set (off) | on only when the debug flag is true |
| `.htaccess` | `php_flag display_errors`, `php_value error_log` | never | never |
| `ini_set()` anywhere | any of the above | never | never |

Rules:

- Production: deprecations go to the log (`docker logs` for containers), never to the screen.
- An API that returns JSON must never receive an HTML error block. Warnings printed through `display_errors` land in the JSON body (seen with a legacy Mongo adapter).
- A `.htaccess` `error_log` pointing at a directory that does not exist loses every log line without a warning (seen in one project).
- `error_reporting` with `~E_DEPRECATED` in production hides exactly the messages you need before the next PHP upgrade. Do not leave it in.
- Keep the masks in one place where you can. If that is not possible, the sweep's R group `error_visibility` lists every site; record which one wins.

Verify after the change:

```bash
docker run --rm IMAGE php -r 'echo ini_get("display_errors"), " ", ini_get("error_reporting"), " ", ini_get("error_log"), PHP_EOL;'
```

Note: this checks the CLI. Web requests also read `.htaccess` and whatever `index.php` sets, so check a web response as well (section 5 and the next paragraph).

Then exercise one page that triggers a notice on purpose (on staging only) and check that it appears in `docker logs`, not in the response.

## 4. php.ini and the zz-custom.ini

Load order: the image's `php.ini` first, then `conf.d/*.ini` in name order, so `zz-custom.ini` wins over earlier files. Keep one custom file, named so it sorts last.

Minimum for a PHP 8 upgrade:

```ini
error_reporting = E_ALL
display_errors = Off
log_errors = On
error_log = /proc/self/fd/2
memory_limit = 512M
upload_max_filesize = 20M
post_max_size = 20M
max_execution_time = 300
expose_php = Off
```

Check that `php -i | grep 'Loaded Configuration File'` names the file you expect, in the built image.

## 5. .htaccess under PHP 8

A generalised `.htaccess` from the reference run. Three blocks.

Block 1, protect non-web files:

```apache
DirectoryIndex index.php
RewriteEngine on
# Never serve dotfiles (.env, .git/, .devcontainer/), build files, or non-web directories.
RewriteRule (^|/)\.(?!well-known/) - [F]
RewriteRule ^(composer\.(json|lock)|Dockerfile|info\.php|readme\.rst|license\.txt|contributing\.md)$ - [F,NC]
# Adjust this directory list to the project's layout.
RewriteRule ^(vendor|docs|cronjob|tests|database|system)(/|$) - [F]
```

Block 2, static assets from `public/` (ask first; route rules can break URLs):

```apache
RewriteCond $1 !\.(php|phtml)$ [NC]
RewriteCond %{DOCUMENT_ROOT}/public/$1 -f
RewriteRule ^(.+)$ public/$1 [END]
```

Block 3, the CodeIgniter front controller:

```apache
RewriteCond $1 !^(index\.php|robots\.txt|favicon\.ico)
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^(.*)$ ./index.php/$1 [L,QSA]
```

PHP directives in `.htaccess` (valid only under mod_php):

```apache
php_value post_max_size 0
php_value upload_max_filesize 0
php_value max_execution_time 0
php_value memory_limit -1
php_value date.timezone <your-timezone>
```

Under php-fpm, move each of these into `php.ini` or the pool. Do not change `memory_limit -1` or `max_execution_time 0` silently. They are production decisions: record them.

Rule: a `php_flag display_errors on` in `.htaccess` overrides the image ini. Remove it.

## 6. CI_ENV and writers of .htaccess

`SetEnv CI_ENV development` in `.htaccess` is read by `index.php` to choose the environment. The reference run's admin configuration page rewrites that line when an admin switches DEV, UAT or LIVE. Deploys do not set `CI_ENV`, so removing the line silently falls back to production.

Before you touch this line:

```bash
grep -rn "CI_ENV" application index.php public/index.php 2>/dev/null
grep -rln "\.htaccess" application 2>/dev/null     # which code writes .htaccess
```

If a writer exists, keep the line and the writer working, and record the risk. If you remove the writer, remove the line in the same commit and state the change in the notes.

## 7. Env files baked into the image

The reference run's CI copies `.env.deploy.dev` (or `.env.deploy.live`) to `.env` before `docker build`. Consequences:

- Changing a value in those files needs a new image build.
- The env file is in git, so secrets in it are in history (report them; do not rewrite history).
- A runtime override works for variables not already present: dotenv with `createUnsafeImmutable` does not overwrite variables already set in the environment. Pass the value with `docker run -e APP_URL=...` for host-specific settings. Check your phpdotenv version and API before relying on this.

## 8. Extensions: install only with a caller

For each extension, find the callers first, then decide.

| Extension | Callers look like | Official `php:*-cli` image | Install with |
|---|---|---|---|
| `imap` | `imap_open`, `imap_*` | Not built in from 8.4 | `install-php-extensions imap` |
| `ftp` | `ftp_connect`, `ftp_*` | Not present (checked on php:8.4-cli) | `docker-php-ext-install ftp` |
| `soap` | `new SoapClient`, `new SoapServer` | Not checked here | `docker-php-ext-install soap` (needs libxml) |
| `oci8` | `oci_*` | Not present | PECL plus Oracle Instant Client. A separate task |
| `redis`, `memcached` | `new Redis`, `Memcached` | Not present | PECL (section 2) |
| `mongodb` | `MongoDB\Driver\Manager` | Not present | PECL tarball (section 2 and 9) |

The reference run installed `imap` but no code loaded the `Imap` library, so the extension was a safety net. That is debt, not safety: record it and let the user decide whether to remove both.

Check what the built image has:

```bash
docker run --rm IMAGE php -m | sort > /tmp/have.txt
# compare with the extensions the code calls (sweep R group ext_*)
```

## 9. ext-mongodb version matching

- Match the extension to the **MongoDB server** version as well as the PHP version. The reference run pins 1.19.4 (its Dockerfile says it still supports MongoDB 3.6 and 4.x and PHP 8.2 to 8.4). A newer extension may not talk to an old server.
- Use the same extension version in dev (`.devcontainer/Dockerfile`) and prod (`Dockerfile`). The reference run's dev container had 2.3.3 while prod had 1.19.4 before the fix, and the mismatch hid bugs.
- The PHP library must match the extension's major version (`mongodb/mongodb` 1.x with ext 1.x; 2.x with 2.x). The mismatch fails on every request with a compile error inside `vendor/mongodb/...`.
- Confirm the compatibility matrix on the driver's release notes for the exact versions. Do not pick versions from memory.

## 10. Composer in the build

The reference run's build ran `composer update` with `--ignore-platform-req=php` and `--no-security-blocking`, and `composer.lock` was ignored on purpose. Consequences:

- Nobody knows which package versions run in production.
- The PHP platform check is off, so a dependency that needs a newer PHP installs and fails at runtime.
- Advisories do not stop the build.

Recommended:

1. Generate and commit `composer.lock` on the target PHP (`composer update` once, then commit).
2. Build with `composer install --no-dev --optimize-autoloader --no-interaction` (no platform ignore).
3. Run `composer validate` and `composer audit` in CI.
4. If the team keeps the lock ignored, write the residual risk in the report.

## 11. CI lint stage

A lint stage that reads the output of every file, both `short_open_tag` modes, and fails on any line other than the OK line: GitLab CI syntax: for another CI system keep the script and change the wrapper. List only directories that exist in the project, because `find` reports a missing one and the job then fails.

```yaml
lint:
  stage: lint
  image: php:8.4-cli          # the production runtime
  script:
    - |
      : > lint.log
      for sot in 0 1; do
        find application cronjob tests public system index.php -name '*.php' \
          ! -path '*/vendor/*' -exec \
          php -d short_open_tag="$sot" -d error_reporting=-1 -d display_errors=1 -d log_errors=0 -l {} \; \
          >> lint.log 2>&1
      done
      if grep -v '^No syntax errors detected' lint.log | grep -q .; then
        cat lint.log
        echo "PHP lint failed (see output above)"
        exit 1
      fi
      echo "PHP lint OK: $(grep -c '^No syntax errors detected' lint.log) results"
  tags:
    - <runner-tag>          # your runner's tag; delete the tags key if your runners take untagged jobs
```

Why this shape:

- `php -l` exits 0 on `Deprecated`. The job reads the output, so deprecations fail it.
- Use `find -exec` rather than `find | xargs -n1 php -l`. GNU `xargs` stops at the first command that exits with status 255, which `php -l` returns on a parse error, so the rest of the files would not be linted. `-exec` runs each file on its own. (This is GNU `xargs` behaviour from its documentation; the skill's `lint-gate.sh` uses `-exec`.)
- Run it on the target version. Add a second job on the next version (8.5) before you claim 8.5 readiness.
- A stage with `allow_failure: true` is not a gate. Remove it once the codebase is clean.
- The lint does not see short tags in HTML-only files or lint-invisible behaviour. Keep the grep sweep as a separate job or as a documented step.

## 12. Local checks without PHP on the host

```bash
# Lint gate (reads output, pass/fail), from the project root
S="<skill-dir>/scripts"      # absolute path of this skill's scripts/ folder
$S/lint-gate.sh 8.4 application index.php    # plus the other PHP paths that exist; a missing path fails the gate
$S/lint-gate.sh 8.5 application index.php
$S/lint-gate.sh --negative-control 8.4

# Runtime facts
docker run --rm php:8.4-cli php -v
docker run --rm php:8.4-cli php -m
docker run --rm php:8.4-cli php -r 'echo function_exists("ftp_connect") ? "ftp\n" : "no ftp\n";'
```

## 13. Smoke environment

Build a throwaway environment with the services the app really uses, on a private Docker network. Use test data. Never point a local copy at production services.

```bash
docker network create php-upgrade-smoke
docker run -d --name smoke-mongo     --network php-upgrade-smoke mongo:4.4      # match the production server version
docker run -d --name smoke-memcached --network php-upgrade-smoke memcached
docker run -d --name smoke-redis     --network php-upgrade-smoke redis:7
```

Build the app image from a **copy** of the repo, with a test `.env` that points at the smoke hosts. Never edit the real repo's `.env` for this. Run it:

```bash
docker run -d --name smoke-app --network php-upgrade-smoke -p 8080:80 -e APP_URL=http://localhost:8080 IMAGE
docker logs -f smoke-app
```

Clean up when done: `docker rm -f smoke-app smoke-mongo smoke-memcached smoke-redis && docker network rm php-upgrade-smoke`.

## 14. Things that go wrong here

| Symptom | Cause | Fix |
|---|---|---|
| HTTP 500 for the whole site after a move to php-fpm | `php_value` or `php_flag` left in `.htaccess` | Move them to `php.ini` or pool config |
| JSON API responses start with `Deprecated:` or `Warning:` | `display_errors` on, often from `.htaccess` or an env flag | Turn it off; keep it on only for explicit debug |
| Logs missing, no error | `error_log` path does not exist | `error_log = /proc/self/fd/2` |
| Site runs the old code after deploy | Container still on the old image | `docker inspect <container> --format '{{.Config.Image}}'` |
| Container name clash removes another environment | Two jobs use the same `docker rm -f` name | Unique names and ports per environment |
| `imap_open` undefined in production | Extension not in the image | `install-php-extensions imap`, after confirming the caller |
| Mongo compile error on every request | Extension and library major versions differ | Align them (section 9) |
| Changed `.env` value has no effect | Value baked into the image | Rebuild, or pass with `-e` |
| Deploy on push you did not intend | CI rule `only: <branch>` with no manual gate | Ask before pushing a deploy branch; read `.gitlab-ci.yml` first |
| Admin "clear cache" deletes the logs | Cache action removes the log directory | Copy the logs first; avoid the button until the investigation is done |
