> Bundled copy from the team's upgrade-ci docs, 2026-10-29. Source of truth: the original docs folder; re-copy to refresh.

# Kinh nghiệm thực tế: nâng namabank lên PHP 8.4

Tài liệu ghi lại những gì đã làm, những gì tài liệu cũ chưa dự đoán và các bẫy gặp phải khi
nâng `namabank` (nhánh `dev-php8427`) từ CodeIgniter 3.1.9 sang fork `hoangkim28/codeigniter`
v0.2.1 và PHP 8.4, trong hai ngày 2026-10-28 và 2026-10-29.
Mục đích: để lần nâng cấp source tiếp theo không phải tìm lại từ đầu.

Đọc kèm [AI_AGENT_PLAYBOOK_PHP8.md](AI_AGENT_PLAYBOOK_PHP8.md),
[UPGRADE_PHP.md](UPGRADE_PHP.md) và [LESSONS_HANMIR_PHP84.md](LESSONS_HANMIR_PHP84.md).
Tài liệu này không liệt kê lại từng thay đổi; danh sách đó nằm trong `docs/upgrade-php84.md`
của repo namabank.

Các phát hiện đều đã đối chiếu với repo, hoặc chạy thử trong container `php:8.4-cli`,
`php:8.5-cli` và `php:8.4.27-apache`. Chỗ chưa kiểm chứng được được ghi rõ ở mục 7.

## 1. Phạm vi và lựa chọn đã chốt

| Hạng mục | Quyết định |
|---|---|
| Framework | Thay `system/` bằng fork `hoangkim28/codeigniter` v0.2.1. `system/` hiện giống hệt bản clone fork trong workspace, không có file ứng dụng lẫn vào, không sửa tay |
| Bootstrap | Không có `application/core/CodeIgniter.php`, không có `WFF_Router` hay hook module. Không cần dựng lại bootstrap |
| Runtime | `php:8.4.27-apache` (mod_php), extension `imap` cài bằng `mlocati/php-extension-installer` |
| ext-mongodb | 1.19.4 cho cả dev (`.devcontainer/Dockerfile`) và prod (`Dockerfile`) |
| Composer | Không commit `composer.lock` (có trong `.gitignore`), build chạy `composer update` |
| Phạm vi kèm theo | Gỡ tính năng chết (chat, Google, Maps, QC, harness) và vá kiểm soát đăng nhập |

Khác với hanmir: namabank **swap core** sang fork (P5 của playbook), không giữ CI 3.1.9
bundled. Vì vậy không có bản vá nào trong `system/`. Phần cần đổi là các class của app kế
thừa framework: `WFF_Log` và `Session_mongo_driver` phải theo interface mới của fork.

### Danh sách commit theo chủ đề

Thứ tự dưới đây là thứ tự thực tế trong `git log` (cũ → mới). Mỗi nhóm được tách commit
riêng để reviewer đọc được.

| Chủ đề | Commit |
|---|---|
| Nền: lên PHP 8.4.27, chuyển sang fork | `6974037b`, `9c9f1f58` |
| Dockerfile, CI, cấu hình lỗi, ext-mongodb dev == prod | `c9f3f7ac` |
| Sửa deprecation và NULL vào hàm internal trong app (132 file) | `03b298d2` |
| Dời `wffdata.json` ra `application/config/`, gỡ `Servicelevel.php` | `90c7a17d`, `0e0d3643` |
| Mongo_db: port các lỗi đã sửa từ jaccs | `88ebb261` |
| `.htaccess`: chặn file dot/build, sửa asset routing | `31e22921`, `5d7bc150` |
| Gỡ `omni_webhook`; thay `google-login-api` bằng `google/apiclient`, rồi gỡ Google | `1b4200af`, `8c10ff7b`, `3ee48dcb` |
| Gỡ chat: `chat_module/` (14.128 file), trạng thái agent, link chi tiết | `f43b1c15`, `dee18517`, `cd9f61cd` |
| Gỡ Google Maps, QC conversation, QC social ticket, controller harness | `f0f60474`, `f90bc1b8`, `0c4424dc`, `983076e7` |
| Vá kiểm soát đăng nhập và phạm vi hàm gọi được qua URL | `8f6de020`, `563fda92`, `57bc616b`, `8216ef3d` |
| Cập nhật ghi chú nâng cấp đi cùng từng thay đổi | `48746e5d`, `b39d2b64`, `6fb6924a`, `f97b9a9e` |

Việc chia song song theo quyền sở hữu file (code app, và Dockerfile/index.php/.htaccess/CI)
và bước kiểm toán đối chiếu với playbook là cách làm của người thực hiện. Phần này không
kiểm chứng được từ git.

## 2. Mười bài học quan trọng nhất

1. **Lint sạch chưa phải là chạy được.** `implode($arr, $glue)` đảo tham số vẫn đúng cú pháp,
   lint không báo. Khi chạy: `Fatal error: Uncaught TypeError: implode(): Argument #1
   ($separator) must be of type string, array given` (đã kiểm trên `php:8.4-cli`). Cùng lớp
   lỗi là NULL vào hàm internal và `count(null)`. Lint chỉ là lớp đầu tiên.
2. **Gate lint phải dựa vào output, không dựa vào exit code.** `php -l` thoát với mã 0 khi
   file chỉ có `Deprecated:` (đã kiểm: `Using ${var} in strings is deprecated`, exit 0). Mẫu
   `php -l ... > /dev/null` trong playbook sẽ báo xanh khi có deprecation. Job `lint` của
   namabank gom toàn bộ output và fail nếu có dòng nào khác `No syntax errors detected`.
3. **Lint không bắt được thẻ `<?` ngắn.** Với `short_open_tag=0`, `<? echo 1 ?>` là HTML thường;
   với `=1`, nó là code hợp lệ. Cả hai chế độ đều "No syntax errors". Chỉ grep trong view mới
   thấy được. Chạy lint với `short_open_tag=1` cho ra lỗi với `<?xml` ở dòng đầu, nên job lint
   vẫn chạy cả hai chế độ.
4. **Deprecation bị giấu ở nhiều nơi, không phải một.** Trước commit `c9f3f7ac`, có ba chỗ tắt
   E_DEPRECATED: `zz-custom.ini` của image (`E_ALL & ~E_DEPRECATED & ~E_STRICT & ~E_NOTICE`),
   `index.php` (`E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED`, ở case development vì live cũng
   chạy `CI_ENV=development`) và `application/config/Dotenv.php` (dòng 32). Sửa một chỗ rồi
   tưởng đã xong là không đủ: chỗ còn lại vẫn ghi đè.
5. **Error handler không được sập khi app chưa khởi tạo xong.** `WFF_Log::notify_error` giờ kiểm
   tra `class_exists('CI_Controller', FALSE)`, rồi `is_object($CI) && isset($CI->load)` trước khi
   gọi `$CI->load->is_loaded()`. Nếu thiếu, một deprecation lúc dựng controller thành 500 và che
   lỗi gốc.
6. **Đọc giá trị thật, đừng tin ghi chú.** `APP_DEBUG` là `true` trong `.env.deploy.dev` và
   `false` trong `.env.deploy.live` (đã kiểm bằng grep tên biến). Từng có ghi chú nói live chạy
   `APP_DEBUG=true`; ghi chú đó sai. Lỗi có hiện trên màn hình hay không do `display_errors`
   quyết định (`Dotenv.php`), không do `CI_ENV`.
7. **`CI_ENV` không xóa được chỉ vì trông như cấu hình thừa.** `.htaccess` có
   `SetEnv CI_ENV development`. `application/controllers/api/v1/Config.php` (dòng 73–76) ghi lại
   dòng này vào `.htaccess` khi admin đổi môi trường (DEV/UAT/LIVE). Deploy không đặt `CI_ENV`,
   nên xóa dòng này là rơi về production. Dòng đã có chú thích "Keep this line as is".
8. **Extension phải khớp server và khớp giữa dev với prod.** Devcontainer đang dùng ext-mongodb
   2.3.3 trong khi prod ghim 1.19.4, bản còn hỗ trợ MongoDB 3.6/4.x. Commit `c9f3f7ac` đưa dev
   về 1.19.4. Chọn bản ext theo phiên bản MongoDB server thật, không chỉ theo PHP.
9. **Xóa tính năng chết thay vì port.** Chat chiếm 14.128 file trong `chat_module/`. Google login
   được thay bằng `google/apiclient` (`8c10ff7b`) rồi gỡ hẳn (`3ee48dcb`). Trước khi xóa phải
   grep caller. Phần DB (Widget, Navigator, Module) không đổi được từ repo nên phải lên lịch
   riêng (mục 6).
10. **Nâng cấp là lúc kiểm soát đăng nhập lộ ra lỗ hổng.** Nhiều controller `extends CI_Controller`
    không gọi `check_login()`: harness gửi SMS và đọc/ghi giao dịch thẻ, Widget CRUD, Monitor,
    `api/namabank/Core` có dữ liệu khách hàng. Đã thêm `check_login()` vào 36 file (chỉ kiểm
    tra đăng nhập, không kiểm tra quyền theo module). Năm endpoint vẫn chưa có, xem mục 7.

## 3. Những gì tài liệu cũ chưa dự đoán

### 3.1. Framework và file nằm sai chỗ

| Vị trí | Vấn đề | Cách sửa |
|---|---|---|
| `system/config/wffdata.json`, `system/config/Servicelevel.php` | File ứng dụng nằm trong framework. Thay `system/` nguyên khối sẽ xóa mất | Dời `wffdata.json` sang `application/config/`, đọc qua `APPPATH` (`namabank.php`, `wff.php`) và writer `api/v1/Config.php`. `Servicelevel.php` là controller chết, xóa (`0e0d3643`) |
| `application/config.bk/` | Bản sao cấu hình cũ | Xóa |
| `E_STRICT` | Deprecated trên 8.4, không fatal (đã kiểm). Gặp ở mọi request nếu còn tham chiếu | Bỏ khỏi `error_reporting()` trong `index.php`. Hết tham chiếu trong code |

### 3.2. Application

| Vị trí | Vấn đề | Cách sửa |
|---|---|---|
| `Mongo_db::add_index()` và chỗ gọi | `implode` đảo tham số, TypeError (xem mục 2.1) | Đã đổi thứ tự. Grep toàn repo không còn `implode($var, ...)` trong app, chỉ còn một chỗ trong vendored build script (mục 8) |
| `WFF_Log::notify_error` | Gọi `$CI->load` khi chưa có | `is_object($CI) && isset($CI->load)` |
| `json_decode($this->input->get/post(...))` | NULL vào hàm internal (8.1). Đã đo: 148 dòng trong tree hiện tại | Thêm `?? ''`. Hiện không còn dòng nào thiếu `??` |
| `curl_close()` | Deprecated 8.5, không có tác dụng từ 8.0. `php -l` không báo, phải grep | Xóa 42 lời gọi (`03b298d2`). Không còn trong code |
| Ép kiểu `(double)`, `(boolean)`, `(integer)` | Deprecated 8.5. `php -l` báo | `(float)`, `(bool)`, `(int)`. Không còn trong code |
| `$http_response_header` | Deprecated 8.5, `php -l` báo. Gợi ý thay bằng `http_get_last_response_headers()` | Chỗ đọc duy nhất nằm trong `omnisales-sdk` (chat), gỡ cùng chat (`f43b1c15`). Cách đọc qua `get_defined_vars()` vẫn đúng cho PHP < 8.4 nếu cần lại |
| `libraries/Imap.php`, `is_resource()` | `imap_open` trả `IMAP\Connection` từ 8.1 | `instanceof \IMAP\Connection \|\| is_resource()`. Nhưng không có nơi nào nạp thư viện này (mục 3.4) |
| `Session_mongo_driver` | Phải implement `CI_Session_driver_interface` của fork | Đã đổi. `sess_driver` = `mongo` |

### 3.3. Dotenv và cấu hình

- phpdotenv v5 dùng `createUnsafeImmutable()` để `getenv()` vẫn đọc được biến từ `.env`. Có
  fallback sang `createImmutable()` khi `vendor/` cũ chưa có v5. Bỏ fallback khi mọi image đã
  build lại.
- `wff_time_cache` có giá trị mặc định 60 trong `wff.php`, nhưng `wff.php` nạp `wffdata.json` bằng
  `array_merge`, nên giá trị từ file JSON (120) thắng. Đây là thời gian cache danh sách widget (mục 6).

### 3.4. Extension và thư viện

| Mục | Thực tế | Hệ quả |
|---|---|---|
| `imap` | Dockerfile cài vì PHP 8.4 không còn build imap trong core. Nhưng không có nơi nào nạp `Imap` library: grep `imap` ngoài `application/config/imap.php` và chú thích Dockerfile không ra kết quả | Cài imap hiện là dự phòng. Nên quyết định: xóa `Imap.php` và extension, hoặc giữ và ghi rõ là dự phòng. `application/config/imap.php` đang được track và có mật khẩu mail (không ghi giá trị ở đây; báo ops) |
| `ftp` | Không có code nào gọi `ftp_*`. `php:8.4-cli` chính thức không có `ftp` (`function_exists('ftp_connect')` là false) | Chỉ cần cài nếu có code gọi |
| `redis` | Không có trong code. `sess_driver` là `mongo` | Không phải rủi ro cho source này |
| `memcached` | Dùng cho cache widget và admin cache (`template/Widget.php`, `api/v1/Cache.php`). Cài bằng PECL trong Dockerfile | Cần test với server thật, xem mục 7 |
| `composer.json` | Chỉ còn `php ^8.4`, `pda/pheanstalk`, `phpoffice/phpspreadsheet`, `vlucas/phpdotenv`. Đã bỏ `mongodb/mongodb`, `alcaeus/mongo-php-adapter`, `google/apiclient` | Ít package phải nâng hơn |

### 3.5. Composer và build

- `composer.lock` bị gitignore có chủ đích. Dockerfile chạy `composer update` lúc build, có các cờ
  `--with-all-dependencies --ignore-platform-req=php --no-security-blocking` (rút gọn).
- Hai cờ cuối làm composer **bỏ qua yêu cầu PHP** và **không chặn package có advisory** khi build.
  Đây là rủi ro: không ai biết đang chạy version nào, và build không dừng khi có lỗ hổng đã công bố.

## 4. Kiểm tra bằng Docker (máy dev không cài PHP)

### 4.1. Gate lint, giống job `lint` của `.gitlab-ci.yml`

```sh
: > /tmp/lint.log
for sot in 0 1; do
  find application cronjob tests public system index.php -name '*.php' -not -path '*/vendor/*' -print0 \
    | xargs -0 -n1 php -d short_open_tag="$sot" -d error_reporting=-1 -d display_errors=1 -l >> /tmp/lint.log 2>&1
done
if grep -v '^No syntax errors detected' /tmp/lint.log | grep -q .; then cat /tmp/lint.log; exit 1; fi
```

Chạy trong container (mount repo chỉ đọc, ghi log vào `/tmp`):
`docker run --rm -v "$PWD":/src:ro php:8.4-cli sh -c 'cd /src && <đoạn trên>'`.
Lặp lại với `php:8.5-cli` khi nâng bản PHP.

**Kiểm chứng gate (negative control).** Trước khi tin gate, chạy đúng logic trên một thư mục
có file kiểm soát:

| Thư mục thử | Kết quả gate |
|---|---|
| Chỉ một file sạch | PASS (2 kết quả, không lỗi) |
| Thêm file `"${b}"` (deprecated) | FAIL, có dòng `Deprecated:` trong output |
| Thêm file thiếu dấu `;` | FAIL, `Parse error`, xargs thoát 255 |

Gate chỉ có ý nghĩa khi đã thấy nó FAIL với một lỗi cố ý.

### 4.2. Lint bắt được gì, không bắt được gì (đã kiểm trên php:8.5-cli)

| Lỗi | `php -l` | Cách bắt |
|---|---|---|
| Cast `(double)`, `(boolean)` | Có (Deprecated) | Lint trên bản đích |
| `$http_response_header` | Có (Deprecated) | Lint trên bản đích |
| `${var}` trong chuỗi | Có (Deprecated) | Lint trên bản đích |
| Thẻ `<?` ngắn | Không, cả hai chế độ | Grep view: `<\?(?!php\|=\|xml)` |
| `<?xml` ở đầu file | Có khi `short_open_tag=1` | Lint hai chế độ |
| Hằng `E_STRICT` | Không (lỗi lúc chạy) | Grep `E_STRICT` |
| `curl_close()` | Không (lỗi lúc chạy) | Grep `curl_close(` |
| `implode` đảo tham số | Không (cú pháp đúng) | Grep + chạy thật |
| `count(null)`, `json_decode(null)` | Không | Smoke test |

### 4.3. Smoke test

Theo `docs/upgrade-php84.md` mục 7: chạy trên PHP 8.4.27 với ext-mongodb 1.19.4 và MongoDB 4.4
tạm trên máy local, vendor không còn adapter. Đã kiểm: `/`, `/page/signin`, route lạ; cookie
`ci_session` (`HttpOnly; SameSite=Lax`), session dùng lại qua nhiều request và id lạ được thay
bằng id mới; `Mongo_db` và `Mongo_private` (insert, get, update, remove, distinct, aggregate,
command); driver `MyMongoDriver` (28 trường hợp); cron CLI; thư viện excel; log ghi vào Mongo.

Chưa có: dữ liệu thật, Mongo UAT/prod, Memcached thật, SMTP, IMAP (không có caller).

## 5. Bẫy CI/CD và deploy

- **Image dev-php8427 gắn tag cố định `:dev`.** `.gitlab-ci.yml` đặt
  `FULLREPO_DEVPHP8427: $CONTAINER_REPO_DEVPHP8427:dev`. Mỗi lần build ghi đè tag, còn job
  deploy `docker pull` đúng tag đó, nên chạy lại một job cũ có thể deploy bản mới hơn. Nên gắn
  tag theo `$CI_COMMIT_SHORT_SHA`, như hanmir (LESSONS_HANMIR_PHP84.md mục 6).
- **`.env` bị đóng vào image.** Các job build chạy `cp .env.deploy.dev .env` (hoặc `.env.deploy.live`)
  trước `docker build`. Đổi giá trị trong `.env.deploy.*` thì phải build lại image.
- **Tên container và cổng tách riêng.** Job dev dùng `4xs-nam-a-bank-dev` (cổng 7772), job
  dev-php8427 dùng `4xs-nam-a-bank-dev-php8427` (cổng 7773). Trước khi thêm job mới, kiểm tra
  tên và cổng để không `docker rm -f` nhầm container đang chạy.
- **Push nhánh `dev-php8427` là deploy.** Job `deploy-dev-php8427` có `only: dev-php8427` và
  không có `when: manual`. Hỏi trước khi push.
- **Lint trong CI chỉ chạy PHP 8.4.** Lint 8.5 chạy tay (mục 4.1).
- **`.htaccess` có `php_value` (không phải php_flag)** vẫn hoạt động vì image `php:8.4.27-apache`
  có `php_module` (mod_php, đã kiểm). Nếu chuyển sang php-fpm, các dòng `php_value` sẽ gây HTTP 500.
- **Log lỗi trỏ vào đường dẫn không tồn tại.** Bản cũ đặt
  `php_value error_log /var/www/html/worldfone4xs/PHP_errors.log`, thư mục đó không có trong image,
  nên log mất im lặng. Bản mới đặt `error_log = /proc/self/fd/2` trong `zz-custom.ini`, log ra
  `docker logs`.
- **Nút "Clear cache" của admin xóa luôn log.** `api/v1/Cache.php` unlink mọi file trong
  `application/logs/` rồi mới xóa cache. Đừng bấm khi còn cần log để điều tra sau deploy.
- **Admin Config ghi `.htaccess` lúc chạy.** Thay đổi này không nằm trong git: image mới sẽ đưa
  file về giá trị trong repo.

## 6. Trước khi deploy: checklist

Thứ tự đã chọn cho namabank. Dữ liệu Mongo nằm ngoài repo, không chạy tự động; cần người giữ DB
xác nhận và thực hiện.

1. **Backup** database trước khi đổi bất kỳ dữ liệu nào.
2. **Tắt widget chết trước khi deploy code xóa view.** Document `Widget` có `name` là
   `chat_status.php` hoặc `messenger.php` (vị trí `LEFT_HEADER_WIDGET` / `RIGHT_HEADER_WIDGET`)
   đặt `active: false`. Lý do: `template/Widget.php` cache danh sách widget 120 giây; nếu view đã
   bị xóa, mọi trang sẽ 500 vì header và sidebar lỗi. Xóa đúng key cache widget, hoặc chờ hết
   120 giây; không dùng "Clear cache" của admin vì nó xóa log (mục 5).
3. **Deploy image** đã build đúng commit.
4. **Gỡ menu và quyền** trỏ tới `manage/chat`, `setting/chat_status_code`, `report/chat/*`,
   `qc/convesation`, `qc/socialticket`, `api/v1/conversation`, `api/restful/conversation`,
   `api/restful/conversationsqc`. Mục còn sót chỉ trả 404 hoặc 403, không làm hỏng trang.
5. **Unset field và drop collection chat** chỉ sau khi xác nhận không còn code hay báo cáo nào
   đọc. Chưa kiểm chứng từ repo; cần người giữ DB xác nhận.
6. **Kiểm tra sau deploy**: `docker inspect <container> --format '{{.Config.Image}}'` đúng image,
   `/` và trang đăng nhập không lỗi, một API có session trả đúng JSON, trước khi đọc log lỗi.

## 7. Chưa kiểm chứng và rủi ro còn lại

| Hạng mục | Trạng thái | Ghi chú |
|---|---|---|
| Lint PHP 8.4 và 8.5, `short_open_tag` 0 và 1 | Đã chạy | Theo `docs/upgrade-php84.md` mục 7: 758 file, không lỗi hay deprecation |
| Smoke test trên local | Đã chạy một phần | Dùng MongoDB 4.4 tạm, không phải dữ liệu UAT/prod |
| **Mongo với dữ liệu và cluster thật** | **Chưa** | **Rủi ro lớn nhất của lần nâng này** |
| Memcached thật (widget cache, admin cache) | Chưa thấy ghi nhận | Code dùng, cần test với server thật |
| Redis | Không áp dụng | Không có trong code |
| Oracle | Không áp dụng | Không có trong Dockerfile |
| IMAP, SMTP, gửi mail | Chưa | Không có caller IMAP. Email nếu có cần test riêng |
| Excel và CSV với dữ liệu thật | Chưa | Mới chạy thư viện trong smoke test |
| Lỗi chỉ lộ lúc chạy (`count(null)`, `ValueError`) | Chưa | Static check không bắt. Smoke test chỉ phủ luồng đã chạy |
| Endpoint chưa có `check_login()` | 5 endpoint | `api/namabank/CheckEmailTicket`, `api/namabank/CheckLogoutIpphone`, `api/wf4x/CheckCallTimeout`, `api/wf4x/Activity` (`moveToLog`), `api/v1/Ping`. Cần quyết định riêng: cron, hook gọi nội bộ, hay bỏ kiểm tra có chủ đích |
| Secret trong repo | Có, báo ops | Tracked: `.env.deploy.dev`, `.env.deploy.live`, `application/config/wffdata.json`, `application/config/imap.php` (có mật khẩu mail). Hằng `secret_key` viết cứng trong `api/namabank/CardServices.php` và `api/wf4x/Agentsign.php`. `googleplus.php` và `chat.php` từng có client secret, đã xóa nhưng còn trong lịch sử git |
| `composer.lock` | Không commit | Build bỏ qua yêu cầu PHP và cảnh báo bảo mật |

Quy tắc với secret: báo ops để xoay khóa. Không tự viết lại lịch sử git.

## 8. Việc còn tồn

| Việc | Ghi chú |
|---|---|
| Quyết định về `Imap.php`, `config/imap.php` và extension imap | Không có caller. Xóa được nếu người phụ trách đồng ý |
| `implode($argv, ' ')` trong `application/third_party/beanstalk/pda/pheanstalk/scripts/build_phar.php:24` | Đảo tham số, vẫn còn. Là script build, không chạy trên request. Lint không thấy |
| Tag image theo commit SHA | Hiện là `:dev` ghi đè |
| Xoay secret và chuyển secret khỏi source | Việc của ops |
| Quyết định cho 5 endpoint chưa đăng nhập | Xem mục 7 |
| `docs/upgrade-php84.md` mục 2, dòng `$http_response_header` | Mô tả cách đọc của code đã gỡ cùng chat. Repo namabank, ngoài phạm vi lần ghi này |
| Hiển thị lỗi trên dev | `APP_DEBUG=true` in Deprecated vào JSON của API. Chỉ dùng cho dev |

## 9. Checklist rút gọn cho source tiếp theo

1. Đối chiếu ext với server: ext-mongodb theo phiên bản MongoDB thật. Dev và prod cùng bản
   (`.devcontainer/Dockerfile` và `Dockerfile`).
2. Gate lint trên bản PHP đích, `short_open_tag` 0 và 1, fail khi output có dòng ngoài
   `No syntax errors detected`. Chạy negative control trước khi tin gate.
3. Grep những thứ lint không thấy: `implode(` đảo tham số (cả `third_party/`), `json_decode(...input->`,
   `curl_close(`, `E_STRICT`, `$http_response_header`, `<?` trong view.
4. Tìm mọi chỗ bật tắt lỗi: `zz-custom.ini`, `index.php`, `Dotenv.php`, `.htaccess`, `ini_set`.
   Ẩn ở một chỗ không đủ.
5. Error handler và logger không được sập khi chưa có `$CI->load`.
6. Trước khi cài extension, grep caller. Extension không có caller là nợ, không phải an toàn.
7. Liệt kê mọi controller, kiểm `check_login()`. Gọi từng endpoint không có session: phải ra
   302/401/403, không được 200.
8. DB theo thứ tự: backup → tắt widget/menu → deploy → unset/drop (mục 6).
9. Image gắn tag theo commit; tên container và cổng không trùng; hỏi trước khi push nhánh có deploy tự động.
10. Sau deploy: kiểm image đang chạy trước khi đọc log lỗi.

## 10. Quy tắc làm việc rút ra

- Đọc giá trị thật trước khi viết vào tài liệu. Chỉ grep tên biến, không in giá trị secret.
- Commit theo chủ đề, mỗi commit một nhóm thay đổi (xem mục 1). Mỗi lần xóa view, controller
  hay route thì ghi phần DB phải làm vào `docs/upgrade-php84.md` trong cùng nhánh.
- Tài liệu đi cùng thay đổi hành vi, không viết sau. Lịch sử `dev-php8427` có commit
  `Update upgrade notes ...` ngay sau mỗi nhóm gỡ tính năng.
- Đừng viết lại lịch sử git khi lộ secret. Báo ops.
- Không tự đổi giá trị cố định với đối tác, và không tự đổi giá trị chỉ vì trông như cấu hình thừa
  (`CI_ENV` trong `.htaccess`, xem mục 2.7).
