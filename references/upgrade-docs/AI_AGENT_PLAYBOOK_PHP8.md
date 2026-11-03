> Bundled copy from the team's upgrade-ci docs, 2026-10-29. Source of truth: the original docs folder; re-copy to refresh.

# Playbook cho AI agent: nâng cấp source CodeIgniter lên PHP 8

Tài liệu này viết cho **một AI agent thực thi**, không phải cho người đọc tham khảo. Mục tiêu: đưa một codebase CodeIgniter kiểu hanmir (CI 3.1.x bundled, PHP 7.x hoặc thấp hơn) về trạng thái của jaccs (core qua Composer, PHP 8.4/8.5, lint sạch).

Tài liệu liên quan, đọc khi được dẫn chiếu, không đọc trước:

| File | Dùng khi |
|---|---|
| `COMPARE_JACCS_HANMIR.md` | Cần biết hiện trạng cụ thể của jaccs và hanmir |
| `UPGRADE_PHP.md` | Cần bảng breaking change theo từng phiên bản PHP |
| `UPGRADE_FROM_3.1.13.md` | Thực thi phase 5, khi app xuất phát từ CI 3.1.x |
| `UPGRADE_FROM_2.2.6.md` | Thực thi phase 5, khi app xuất phát từ CI 2.2.6 |
| `README.md` | Cảnh báo về nhãn phiên bản `3.4.5` của fork |

## 0. Hợp đồng thực thi

Agent nhận playbook này phải tuân thủ các điều sau. Đây là ràng buộc, không phải gợi ý.

1. **Làm tuần tự theo phase.** Không nhảy phase. Mỗi phase có acceptance criteria riêng ở mục 10; chưa đạt thì không sang phase sau.
2. **Mỗi phase là một commit riêng** trên một nhánh riêng (`upgrade/php8`). Không trộn nhiều phase vào một commit, vì rollback sẽ không tách được.
3. **Không bịa số liệu.** Mọi con số trong báo cáo phải kèm lệnh đã chạy và output thật. Nếu không chạy được lệnh, ghi rõ "chưa kiểm chứng" thay vì ước lượng.
4. **Không xóa hay ghi đè khi chưa đọc đích.** Đặc biệt với `system/`: xem mục 5.1, có file của ứng dụng nằm lẫn trong đó.
5. **Không tự ý đổi logic nghiệp vụ.** Phạm vi là tương thích PHP và framework. Gặp bug nghiệp vụ thì ghi vào báo cáo, không sửa.
6. **Dừng và hỏi người** trong các trường hợp ở mục 12.
7. **Không chạy trên production.** Mọi thao tác trên nhánh riêng và môi trường staging.

## 1. Bối cảnh

- **Bản mẫu đã hoàn thành: jaccs** (`<path>/jaccs`). Đã chuyển core sang Composer, chạy PHP 8.5, `php -l` sạch trên 8.3/8.4/8.5. Dùng làm nguồn đối chiếu cho mọi quyết định.
- **Mục tiêu điển hình: hanmir** (`<path>/hanmir`). CI 3.1.9 bundled, core bị vá trực tiếp, bootstrap bị copy, PHP 7.x, Apache với mod_php.
- **Core đích:** fork cộng đồng `hoangkim28/codeigniter`, `CI_VERSION = '3.4.5'`.
  - Repo gốc: <https://github.com/hoangkim28/codeigniter>
  - Bản clone cục bộ để tra cứu: `<path>/upgrade-ci/hoangkim28-codeigniter` (nhánh `develop`, clone `--depth 1`)
  - Packagist: `hoangkim28/codeigniter`, phiên bản `v0.2.1` (2026-10-23)
  - **Không phải bản phát hành chính thức của BCIT.** EllisLab/BCIT không phát hành 3.2, 3.3 hay 3.4. Fork này xây trên nhánh `3.2.0-dev` chưa phát hành của upstream, thông qua `pocketarc/codeigniter`. Đọc mục 2 của `README.md` trước khi pin phiên bản.
- **Tree tham chiếu khác trong workspace:**
  - `<path>/upgrade-ci/codeigniter-2.2.6` — bcit-ci/CodeIgniter tag `2.2.6`, <https://github.com/bcit-ci/CodeIgniter/tree/2.2.6>
  - `<path>/upgrade-ci/codeigniter-3.1.13` — bcit-ci/CodeIgniter tag `3.1.13`, <https://github.com/bcit-ci/CodeIgniter/tree/3.1.13>

## 2. Sơ đồ phase

```
Phase 0  Khảo sát và lập inventory            → không sửa file nào
Phase 1  Dựng lưới an toàn                    → baseline tag, lint trong CI, staging
Phase 2  Sửa nhóm fatal                       → vẫn chạy PHP cũ
Phase 3  Nâng package Composer                → vẫn chạy PHP cũ
Phase 4  Lint trên PHP 8.3 ở dev              → chưa đổi framework, chưa deploy
Phase 5  Đổi core sang hoangkim28/codeigniter → deploy staging
Phase 6  Nâng runtime lên 8.4 rồi 8.5         → xử lý extension chuyển PECL
Phase 7  Dọn deprecation và bàn giao
```

Lý do tách phase 4 và 5: CI 3.1.x không chạy sạch trên PHP 8 (thiếu `#[AllowDynamicProperties]`, `SessionHandlerInterface` chưa có wrapper mới). Phase 4 chỉ để **phát hiện** lỗi tầng ứng dụng ở dev, không deploy. Production chỉ chạy PHP 8 sau phase 5.

## 3. Phase 0 — Khảo sát

Không sửa file nào trong phase này. Sản phẩm là một file inventory.

### 3.1 Lệnh bắt buộc chạy

Thay `$APP` bằng đường dẫn repo đích.

```bash
# Phiên bản framework đang dùng
grep -rn "CI_VERSION" "$APP/system/core/CodeIgniter.php" 2>/dev/null
grep -n "system_path\|application_folder\|view_folder" "$APP/index.php"
ls "$APP"/*/index.php 2>/dev/null          # có entry point thứ hai không

# Core có bị vá không: diff với tree gốc đúng phiên bản
diff -rq "$APP/system" <path>/upgrade-ci/codeigniter-3.1.13/system | head -50

# Bootstrap có bị copy vào application không
ls -la "$APP/application/core/"
grep -rn "APPPATH.*CodeIgniter.php" "$APP/index.php" "$APP"/*/index.php 2>/dev/null

# Core extension của ứng dụng
grep -n "subclass_prefix" "$APP/application/config/config.php"
ls "$APP/application/core" "$APP/application/hooks" 2>/dev/null

# Package
cat "$APP/composer.json" 2>/dev/null
ls "$APP/composer.lock" "$APP/vendor" 2>/dev/null || echo "KHONG CO LOCK HOAC VENDOR"

# Thư viện copy tay
ls "$APP/application/third_party" 2>/dev/null

# Runtime thật, chạy trong container production, không tin tên image
# docker exec <container> php -v
# docker exec <container> php -m
```

### 3.2 Quét lỗi PHP 8

Chạy toàn bộ, ghi lại số lượng và `file:line`. Dùng `rg` nếu có, `grep -rn` nếu không.

```bash
cd "$APP"
S="application modules cronjob"   # bỏ modules nếu app không có HMVC

# Nhóm fatal trên PHP 8.0
rg -n --type php 'implode\s*\(\s*\$[A-Za-z_]' $S            # nghi ngờ implode đảo tham số
rg -n --type php '\bmysql_[a-z_]+\s*\(' $S
rg -n --type php '\b(ereg|eregi|split|each|create_function|money_format|get_magic_quotes_gpc)\s*\(' $S
rg -n --type php '\bmcrypt_[a-z_]+\s*\(' $S
rg -n --type php '\$HTTP_RAW_POST_DATA' $S
rg -n --type php '\$[A-Za-z_]+\{[0-9]' $S                   # string offset kiểu cũ
rg -n --type php 'function\s+([A-Z][A-Za-z_]*)\s*\(' $S     # nghi ngờ constructor PHP 4, phải đối chiếu tên class

# Nhóm deprecated 8.1 - 8.2
rg -n --type php '\$\{[A-Za-z_]' $S                         # nội suy ${var}, lọc bỏ template literal của JS
rg -n --type php '\b(utf8_encode|utf8_decode|strftime|date_sunrise|date_sunset)\s*\(' $S
rg -n --type php 'FILTER_SANITIZE_STRING' $S
rg -n --type php '\bis_resource\s*\(' $S                    # vỡ với imap_open, curl_init từ 8.1
rg -n --type php 'implements\s+[^{]*\b(ArrayAccess|Iterator|IteratorAggregate|Countable|JsonSerializable|SessionHandlerInterface)\b' $S

# Nhóm deprecated 8.4 - 8.5: curl_close và E_STRICT lint không báo; cast và $http_response_header lint báo nhưng vẫn nên grep để đếm
rg -n --type php '\bcurl_close\s*\(' $S
rg -n --type php '\bE_STRICT\b' $S
rg -n --type php '\((double|boolean|integer|binary)\)' $S
rg -n --type php '\$http_response_header' $S

# Tham số bắt buộc sau tham số có default
rg -n --type php 'function\s+\w+\s*\([^)]*=\s*[^,)]+,\s*\$\w+\s*[,)]' $S

# Truyền NULL vào hàm internal
rg -n --type php 'json_decode\s*\(\s*\$this->input->(post|get)\(' $S
rg -c --type php '\b(count|sizeof)\s*\(' $S

# Short tag trong view
rg -n --type php '<\?(?!php|=|xml)' application/views $S

# Extension đang dùng
rg -no --type php '\b(imap|oci|ftp|curl|mongodb|redis|rd_kafka|gd|soap)_[a-z_]+\s*\(' $S | sort -u | head -40
```

**Cảnh báo false positive, đã gặp thật:**

- `${` trong view phần lớn là template literal của JavaScript. Ở hanmir, 1300 hit là JS, chỉ 7 hit là PHP thật.
- `each(` thường là `$.each(` của jQuery và `foreach`. Ở hanmir, khoảng 1200 hit thô đều là false positive; chỉ regex có ranh giới từ mới lọc đúng.
- `split(` có thể là tên method tự định nghĩa, không phải hàm built-in đã bị gỡ.
- `mcrypt_*` và `create_function` trong thư viện vendored thường nằm sau guard `function_exists` hoặc `version_compare`, nên không chạm trên PHP 8. Phải đọc ngữ cảnh trước khi tính vào danh sách phải sửa.
- Constructor kiểu PHP 4 chỉ là lỗi khi class **không** có `__construct()` đi kèm.

Mọi con số đưa vào báo cáo phải là **số sau khi lọc false positive**, kèm ghi chú đã lọc bằng cách nào.

### 3.3 Mẫu inventory phải nộp

```markdown
# Inventory: <tên app>
## 1. Baseline
- CI_VERSION: ...   (lệnh: ...)
- Nguồn core: bundled / composer, đường dẫn: ...
- PHP runtime thật: ...   (lệnh: docker exec ... php -v)
- Extension có trong image: ...   (lệnh: php -m)
- Web server: ...
## 2. Core bị vá
| File | Nội dung sửa | Xử lý |
## 3. Core extension của ứng dụng
| Class | Parent | Constructor | Override | Tương thích fork |
## 4. Package
| Package | Ràng buộc | Version lock | Tương thích PHP 8 |
## 5. Lỗi PHP 8 theo nhóm
| Nhóm | Số lượng sau lọc | file:line | Cách sửa |
## 6. Extension code dùng nhưng image thiếu
## 7. Chưa kiểm chứng được
```

## 4. Phase 1 — Dựng lưới an toàn

Làm trước khi chạm vào bất kỳ dòng code nào.

1. Tạo tag baseline trên commit đang chạy ổn: `git tag baseline-php7 && git push origin baseline-php7`.
2. Tạo nhánh làm việc: `git checkout -b upgrade/php8`.
3. Thêm stage lint vào pipeline. Tối thiểu:

```yaml
lint:
  image: php:8.4-cli      # hoặc bản PHP đích
  script:
    - |
      : > lint.log
      for sot in 0 1; do
        find application modules -name '*.php' -print0 \
          | xargs -0 -n1 php -d short_open_tag="$sot" -d error_reporting=-1 -d display_errors=1 -l >> lint.log 2>&1
      done
      if grep -v '^No syntax errors detected' lint.log | grep -q .; then cat lint.log; exit 1; fi
    - composer validate --no-check-publish
  allow_failure: true     # bỏ allow_failure sau phase 4
```

Không dùng `php -l > /dev/null` và chỉ tin exit code: `php -l` thoát 0 khi file chỉ có `Deprecated` (đã kiểm trên `php:8.4-cli`). Gate phải đọc output.

4. Dựng staging có đủ dependency ngoài: Mongo, Redis, Memcached, beanstalkd, Oracle — tùy app. Lint không thay được chạy thật.
5. Ở staging: bật `error_reporting(E_ALL)`, **tắt** `display_errors`, ghi vào log. Với app trả JSON, Warning của PHP 8 sẽ lẫn vào response body nếu `display_errors` bật.
6. Kiểm tra `.htaccess`: nếu còn `php_flag` hoặc `php_value` mà hạ tầng đích là php-fpm, các dòng đó gây **HTTP 500**. Chuyển sang `php.ini` hoặc pool config. Image `php:*-apache` chính thức chạy mod_php, nên các dòng này vẫn có hiệu lực ở đó (namabank đã kiểm: `php_module` được nạp).

## 5. Phase 2 — Sửa nhóm fatal

Vẫn chạy PHP cũ. Mục tiêu: sau phase này, code không còn construct nào fatal trên PHP 8.

### 5.1 Việc phải làm trước tiên: cứu file ứng dụng nằm trong `system/`

Đã gặp ở cả hai codebase. `system/config/wffdata.json` và `wffdata.example.json` nằm trong thư mục framework, được code đọc lúc chạy. Thay `system/` nguyên khối sẽ xóa mất chúng.

```bash
# Tìm mọi file không thuộc framework nằm trong system/
diff -rq "$APP/system" <path>/upgrade-ci/codeigniter-3.1.13/system | grep "^Only in $APP"
# Tìm nơi code đọc chúng
rg -n 'BASEPATH\s*\.' "$APP/application" "$APP/modules" 2>/dev/null
```

Di dời sang `application/config/`, sửa mọi nơi đọc, commit riêng, xác nhận app vẫn chạy **trước khi** sang bước khác.

Lưu ý bảo mật: các file này thường chứa secret và đang được track trong git. Ghi vào báo cáo để đội vận hành xoay vòng khóa; không tự ý xóa khỏi lịch sử git.

### 5.2 Bảng sửa theo nhóm

| Nhóm | Cách sửa | Mức rủi ro hồi quy |
|---|---|---|
| `implode($array, $glue)` | Đổi thành `implode($glue, $array)` | Thấp, sửa cơ học |
| Hàm đã bị gỡ (`mysql_*`, `ereg*`, `split`, `each`, `create_function`, `money_format`, `get_magic_quotes_gpc`, `mcrypt_*`) | Xem bảng 3.1 và 3.2 của `UPGRADE_PHP.md` | Trung bình, phải test chức năng |
| Constructor kiểu PHP 4 | Đổi sang `__construct()` | Thấp |
| `$str{0}` | `$str[0]` | Thấp |
| `assert('chuỗi')` | Truyền biểu thức | Thấp |
| Short tag `<?` trong view | Đổi sang `<?php`. Fork đã bỏ `rewrite_short_tags` nên không cứu được bằng config | Thấp |
| `$HTTP_RAW_POST_DATA` | `file_get_contents('php://input')` | Thấp |
| Tham số bắt buộc sau tham số có default | Bỏ default của tham số đứng trước | Thấp, nhưng phải grep mọi caller |

### 5.3 Nhóm khối lượng lớn: NULL vào hàm internal

Đây là nhóm tốn công nhất. Ở hanmir có trên 210 vị trí, phần lớn là `json_decode($this->input->post('x'))`.

Nguyên tắc sửa:

```php
// Sai trên PHP 8.1+: post() trả NULL khi thiếu key
json_decode($this->input->post('data'), true);

// Đúng
json_decode((string) $this->input->post('data'), true);
// hoặc
json_decode($this->input->post('data') ?? '', true);
```

Với `count()`: `count(null)` là `TypeError` trên PHP 8.0. Guard bằng `is_array($x) || $x instanceof Countable` trước khi đếm, hoặc `count($x ?? [])`.

Chia theo module, mỗi module một commit, để review được.

## 6. Phase 3 — Nâng package Composer

1. Nếu chưa có `composer.json` hợp lệ hoặc chưa có `composer.lock`, tạo và **commit lock**. Không có lock thì không ai biết đang chạy version nào.
2. Đặt `"php": "^8.4"` trong `require`.
3. Nâng từng package, ưu tiên nhóm này vì chúng tự xóa nhiều lỗi ở tầng ứng dụng:

| Package | Bản tối thiểu cho PHP 8.x | Việc kèm theo |
|---|---|---|
| `phpoffice/phpspreadsheet` | 1.2x hoặc 2.x. Lưu ý 2.4.7 yêu cầu `<8.6.0` | Đổi namespace nếu đang từ PHPExcel |
| `mongodb/mongodb` | 1.15+ (ext 1.21 cho PHP 8.4) | Kiểm tra version ext-mongodb trong image. Chọn ext theo phiên bản MongoDB server thật, không chỉ theo PHP: namabank giữ ext 1.19.4 cho server 3.6/4.x, và dev dùng cùng bản |
| `vlucas/phpdotenv` | 5.x | API `Dotenv::createImmutable` |
| `firebase/php-jwt` | 6.x | Đổi `decode($jwt, new Key($key, $alg))` |
| `predis/predis` | 1.1.10+ hoặc 2.x | |
| `dompdf/dompdf` | 1.x hoặc 2.x | |
| `phpoffice/phpword` | 0.18 hoặc 1.x | |
| `pda/pheanstalk` | 4.x (PHP 7.1+) hoặc 5.x (PHP 8.1+) | v4 và v5 đổi API, wrapper phải viết lại |
| `dragonmantank/cron-expression` | 3.x | |
| `league/oauth2-client` | 2.6+ | |
| `phpunit/phpunit` (dev) | 9.x trở lên | Bản 4/5 không chạy trên PHP 8 |

4. Thay package abandoned:

| Abandoned | Thay bằng | Ghi chú |
|---|---|---|
| `opis/closure` 3.x | `laravel/serializable-closure` | Code nào kế thừa `SerializableClosure` và dùng internal (`$scope`, `$reference`, `getReflector`, `securityProvider`) phải viết lại |
| `simplario/quedis` | Tự implement hoặc dùng queue sẵn có | |
| phpseclib 1.0.x copy tay | `phpseclib/phpseclib` v3 qua Composer | API AES đổi hoàn toàn; tìm mọi chỗ `require` file phpseclib trực tiếp |

5. Nếu app có nhiều bản copy của cùng một library (jaccs có 6 bản `Mongo_db`/`Mongo_private` trong `cronjob/`), gộp về một nguồn hoặc ít nhất đồng bộ bản vá. Sửa một bản rồi quên các bản còn lại là lỗi đã xảy ra thật.

## 7. Phase 4 — Lint trên PHP 8.3

Chưa đổi framework, chưa deploy. Chỉ để phát hiện lỗi tầng ứng dụng.

```bash
# Lint chéo phiên bản bằng Docker, không cần cài lên host
for V in 8.3 8.4 8.5; do
  echo "=== PHP $V ==="
  docker run --rm -v "$APP":/app:ro "php:$V-cli" sh -c \
    'find /app/application /app/modules -name "*.php" -print0 2>/dev/null | xargs -0 -n1 php -d error_reporting=-1 -d display_errors=1 -l | grep -v "^No syntax errors"'
done
```

Thêm quét sâu hơn:

```bash
composer require --dev phpcompatibility/php-compatibility
vendor/bin/phpcs -p application modules --standard=PHPCompatibility --runtime-set testVersion 8.4-
```

Rector dùng được cho nhóm cú pháp, nhưng **chạy trên nhánh riêng và review từng commit**; không merge thẳng output của Rector.

Lint không bắt được: NULL vào hàm internal, `count()` trên giá trị không đếm được, so sánh `0 == "abc"`, truy cập mảng trên `null` hoặc `false`, `+=` trên chuỗi, gọi static vào method non-static. Những lỗi này chỉ lộ khi chạy thật ở staging. Lint cũng không báo thẻ `<?` ngắn ở cả hai chế độ `short_open_tag`, nên view cần grep riêng (mục 3.2). Gate chỉ đạt khi output không có dòng nào ngoài `No syntax errors detected`, kể cả `Deprecated`.

## 8. Phase 5 — Đổi core sang fork

Chi tiết thao tác nằm ở `UPGRADE_FROM_3.1.13.md` (hoặc `UPGRADE_FROM_2.2.6.md`). Phần dưới chỉ là các điểm đặc thù mà agent hay bỏ sót.

### 8.1 Cài core

```bash
composer require hoangkim28/codeigniter:^0.2
```

Rồi sửa `$system_path` trong mọi entry point và file test:

```bash
rg -n 'system_path|/system' "$APP/index.php" "$APP"/*/index.php "$APP/tests" 2>/dev/null
```

Ở jaccs, đường dẫn này xuất hiện tại `index.php:123`, `tests/Bootstrap.php:7`, khoảng 20 file trong `tests/**` và `tests/security/composer_contract_test.php:9`. Sửa thiếu một chỗ là test gãy mà không rõ lý do.

Sau khi chuyển, xóa `system/` khỏi repo. Trước khi xóa: đã hoàn thành mục 5.1 chưa.

**Ràng buộc rollback:** khi `system/` không còn trong repo, rollback phụ thuộc `composer install`. Xác nhận có mirror nội bộ hoặc `vendor/` đóng gói sẵn trong image, nếu không rollback sẽ kẹt.

### 8.2 Bootstrap bị copy

Nếu `application/core/CodeIgniter.php` tồn tại và entry point trỏ vào đó thay vì `BASEPATH`:

1. Diff bản copy với bootstrap gốc đúng phiên bản để tách ra **chỉ những thay đổi của ứng dụng**.
2. Rebase: lấy `system/core/CodeIgniter.php` của fork làm nền, re-apply đúng các thay đổi đó.
3. Xóa các block chết theo phiên bản, ví dụ `!is_php('5.4')` có tham chiếu `$HTTP_RAW_POST_DATA`.
4. Điểm **bắt buộc kiểm tra**: bản copy cũ gọi `load_class('Hooks'|'Utf8'|'URI'|'Security'|'Input','core')` không tham số. Fork đổi constructor sang nhận dependency, nên giữ nguyên sẽ fatal.

### 8.3 Core extension phải sửa

Fork đổi chữ ký constructor của `CI_Hooks`, `CI_URI`, `CI_Utf8`, `CI_Security`, `CI_Input`. Mọi subclass (`MY_*` hoặc prefix tự đặt như `WFF_`) định nghĩa `__construct()` và gọi `parent::__construct()` không tham số sẽ ném `ArgumentCountError`.

```bash
rg -n 'class\s+(MY_|WFF_)?(Hooks|URI|Utf8|Security|Input|Log|Loader|Router|Output|Session)\b' "$APP/application"
```

| Class | Chữ ký đúng trên fork |
|---|---|
| `Hooks` | `__construct(CI_Config $config)` |
| `URI` | `__construct(CI_Config $config)` |
| `Utf8` | `__construct($charset)` |
| `Security` | `__construct($charset)` |
| `Input` | `__construct(CI_Security &$security)` |

Với subclass của `CI_Log`: fork đã thay `$this->_file_ext` bằng `_log_filename` và `_log_filename_dated`. Subclass nào copy nguyên `write_log()` sẽ **hỏng âm thầm** — file log sai tên và mất header chặn truy cập. Cách sửa đúng: giữ lại phần side-effect riêng của ứng dụng rồi `return parent::write_log($level, $msg)`.

Với subclass copy nguyên `xss_clean()` của `CI_Security`: thu gọn thành wrapper mỏng gọi `parent::xss_clean()`, giữ lại đúng phần guard riêng.

### 8.4 Session driver tự viết

Đây là điểm vỡ chắc chắn khi app dùng session driver riêng (Mongo, Redis tùy biến...).

Fork đổi `CI_SessionWrapper::__construct(CI_Session_driver_interface $driver)` — type-hint interface mới. Driver cũ chỉ `implements SessionHandlerInterface` sẽ không khớp.

Phải có:

```php
class CI_Session_mongo_driver extends CI_Session_driver
    implements SessionHandlerInterface, CI_Session_driver_interface
{
    // open, read, write, close, destroy, gc  — đã có
    // bổ sung:
    #[\ReturnTypeWillChange]
    public function updateTimestamp($id, $data) { /* ... */ }

    #[\ReturnTypeWillChange]
    public function validateId($id) { /* ... */ }
}
```

Kiểu trả về phải đúng `bool` vì wrapper PHP 8 khai báo `: bool`.

**Nếu đang nâng cấp một app cùng dòng sản phẩm với jaccs:** port thẳng `application/libraries/Session/drivers/Session_mongo_driver.php` từ jaccs thay vì viết lại. Bản đó đã implement đủ interface và đã chạy production.

### 8.5 Driver cache tùy biến

Nếu app từng vá `system/libraries/Cache/Cache.php` để thêm driver vào `$valid_drivers`, **không vá lại core**. Tạo subclass ở tầng ứng dụng, ví dụ `application/libraries/Cache/WFF_Cache.php`, override `$valid_drivers`.

### 8.6 Thay đổi hành vi phải test, không phát hiện được bằng lint

| Thay đổi của fork | Cách tìm chỗ bị ảnh hưởng |
|---|---|
| Biến view không còn rò sang view nạp sau | `rg -n 'load->view\(' --type php \| wc -l` và đếm `load->vars(`. App có nhiều `load->view()` một tham số mà không dùng `load->vars()` là rủi ro cao |
| `(:any)` đổi từ `.+` thành `[^/]+` | `rg -n '\(:any\)' application/config/routes.php`. Route cần khớp cả dấu `/` phải đổi sang `(.+)` |
| Bỏ lọc input toàn cục (`_sanitize_globals`) | Mọi nơi echo `$_SERVER['PHP_SELF']`, `$_GET`, cookie mà không escape |
| `where_in` family yêu cầu `array` | `rg -n 'where_in\(\|or_where_in\(\|where_not_in\('` — mảng rỗng nay ném `InvalidArgumentException` |
| Lỗi kết nối DB ném `RuntimeException` | Mọi `load->database()` thủ công cần `try/catch` |
| Output cache đổi định dạng khóa | Xóa `application/cache` khi cut-over |
| Email `validate` mặc định `TRUE` | Test gửi mail, địa chỉ sai trước đây lọt nay sẽ fail |

## 9. Phase 6 — Nâng runtime lên 8.4 rồi 8.5

1. Dựng base image mới. Mẫu tham chiếu: `docker/Dockerfile.base` của jaccs (Alpine 3.24, `php85-*`). Nhưng app có `oci8` hoặc `rdkafka` thì phải build thêm PECL, không dùng lại image của jaccs nguyên trạng.
2. **Extension `imap` đã rời core PHP từ 8.4.** Cài `php85-pecl-imap` hoặc tương đương. Bỏ qua bước này thì tính năng mail hỏng âm thầm.
3. Đối chiếu extension code dùng với `php -m` trong image đã build:

```bash
docker run --rm <image> php -m > /tmp/have.txt
# so với danh sách thu được ở mục 3.2
```

Lỗi đã gặp thật ở jaccs: code gọi `ftp_connect` và `imap_open` nhưng image không cài `ftp` lẫn `imap`. Hai tính năng hỏng âm thầm, không ai phát hiện vì production tắt deprecation.

4. Sửa nhóm riêng của 8.4 và 8.5:

| Việc | Phiên bản |
|---|---|
| `function f(Foo $x = null)` đổi thành `?Foo` | 8.4 |
| Bỏ `E_STRICT` khỏi `error_reporting()` trong `index.php` tự viết | 8.4 |
| Gỡ `curl_close()` | 8.5 |

5. Kiểm tra `error_reporting` ở production. Nếu đang là `E_ALL & ~E_NOTICE & ~E_DEPRECATED` thì mọi deprecation bị giấu. Tạm bật đầy đủ ở staging trước mỗi lần nâng phiên bản.

## 10. Acceptance criteria từng phase

Agent không được báo hoàn thành một phase khi chưa có bằng chứng tương ứng.

| Phase | Điều kiện đạt | Bằng chứng phải nộp |
|---|---|---|
| 0 | Inventory đầy đủ 7 mục của mẫu 3.3 | File inventory kèm lệnh đã chạy |
| 1 | Có tag baseline, nhánh riêng, stage lint trong pipeline, staging chạy được | `git tag -l`, link pipeline, URL staging |
| 2 | Toàn bộ nhóm fatal về 0 sau lọc false positive | Output grep trước và sau |
| 3 | `composer validate` pass, `composer.lock` đã commit, không còn package abandoned | Output `composer validate`, `composer show -o` |
| 4 | `php -l` sạch trên 8.3 cho toàn bộ `application` và `modules` | Output lệnh lint, không cắt bớt |
| 5 | App chạy được trên staging với core fork; đăng nhập, session, route chính hoạt động | Log staging, danh sách case đã test |
| 6 | `php -l` sạch trên 8.4 và 8.5; `php -m` có đủ extension code dùng | Output cả hai lệnh |
| 7 | Deprecation log ở staging trống trong một chu kỳ chạy đầy đủ | Trích log |

## 11. Danh sách test bằng tay bắt buộc

Lint và unit test không phủ được các mục này. Phải test thủ công sau phase 5 và sau phase 6.

- Đăng nhập, đăng xuất, remember-me, regenerate session qua AJAX. Session driver tự viết là phần dễ vỡ nhất.
- Gửi và nhận mail qua IMAP và SMTP.
- Xuất Excel và CSV (PhpSpreadsheet đổi major version).
- Tải file lên và tải về qua route có `(:any)`.
- Worker và cron chạy dài: tên file log có roll over đúng ngày không.
- Mọi API trả JSON: xác nhận không có Warning của PHP lẫn trong body.
- Nếu app có kiến trúc module tự chế: test **toàn bộ** module, vì routing đi qua bootstrap tự viết.
- Thanh toán, webhook, callback từ bên thứ ba: nếu bật CSRF, cookie `SameSite=Strict` của fork sẽ chặn POST cross-site. Thêm vào `csrf_exclude_uris`.
- Kiểm quyền truy cập: lấy danh sách endpoint bằng grep `check_login()` trên mọi controller, không chỉ đọc các file nghi ngờ. Gọi từng endpoint không có session: kết quả phải là 302, 401 hoặc 403, không được 200. Namabank thêm `check_login()` vào 36 controller trong lần nâng này và còn 5 endpoint chưa có, xem `LESSONS_NAMABANK_PHP84.md` mục 7.

## 12. Khi nào phải dừng và hỏi người

Dừng, báo cáo, chờ xác nhận — không tự quyết:

1. Phát hiện secret trong repo (`.env` được track, credential hard-code, khóa API trong file config). Báo để đội vận hành xoay vòng khóa. **Không tự viết lại lịch sử git.**
2. Phải đổi logic nghiệp vụ để code chạy được trên PHP 8.
3. Phiên bản runtime thật khác với tên image hoặc khác với khai báo trong `composer.json`. Đã gặp ở hanmir: code gọi hàm chỉ có trên PHP 8 trong khi image mang tên PHP 7.
4. Thư viện vendored không xác định được phiên bản và không có bản thay thế trên Composer.
5. Phải xóa file đang được track trong git mà chưa rõ ai dùng.
6. Quyết định pin phiên bản fork: nhánh `develop` chỉ có một commit, không truy vết được lịch sử. Pin theo commit hoặc tag cụ thể, và thống nhất với người sở hữu fork ý nghĩa của nhãn `3.4.5`.
7. Sau phase 5, có test nghiệp vụ fail mà nguyên nhân không nằm trong phạm vi tương thích.

## 13. Cạm bẫy đã gặp thật

Danh sách này lấy từ khảo sát jaccs và hanmir. Đọc trước khi bắt đầu để không lặp lại.

| Cạm bẫy | Hậu quả |
|---|---|
| Thay `system/` nguyên khối | Xóa mất file cấu hình của ứng dụng nằm lẫn trong đó |
| Sửa một bản copy của library, quên các bản còn lại | jaccs sửa `implode()` trong `application/libraries` nhưng còn 5 bản trong `cronjob/` vẫn fatal |
| Tin tên Docker image để suy ra phiên bản PHP | hanmir mang tên `php7-*` nhưng code đã gọi hàm chỉ có trên PHP 8 |
| Giữ `php_flag`/`php_value` trong `.htaccess` khi chuyển sang php-fpm | HTTP 500 toàn site |
| Bật `display_errors` trong image production (qua `.htaccess`, `ini_set` hoặc `index.php`) | Warning của PHP 8 in thẳng vào response JSON của API. `CI_ENV=development` chỉ là một điều kiện; công cụ admin có thể ghi lại dòng này (namabank: `api/v1/Config.php`), nên đừng xóa mà không kiểm |
| Đặt `error_reporting` giấu `E_DEPRECATED` ở production | Lỗi tích tụ không ai thấy cho tới khi nâng phiên bản kế tiếp |
| Tin `changelog.rst` của fork | Changelog ghi đã gỡ nhiều thứ mà code thực tế vẫn giữ. **Tin code, không tin changelog** |
| Đếm hit grep thô rồi báo cáo | Sai một bậc độ lớn do false positive từ JavaScript trong view |
| Bỏ qua extension chuyển sang PECL | `imap` rời core từ 8.4; tính năng mail hỏng âm thầm |
| Quên `composer.lock` | Không ai biết production đang chạy version package nào |
| `.htaccess` có `php_value error_log` trỏ tới đường dẫn không tồn tại | Log lỗi mất im lặng, không có cảnh báo nào |
| Gate lint chỉ dựa vào exit code (`php -l > /dev/null`) | `php -l` thoát 0 khi chỉ có `Deprecated`: gate báo xanh với deprecation |
| Nút xóa cache của admin xóa cả thư mục log | Mất log cần để điều tra sau deploy (namabank: `api/v1/Cache.php`) |

## 14. Mẫu báo cáo bàn giao

```markdown
# Báo cáo nâng cấp PHP 8: <tên app>
## Phạm vi
- Từ: CI <x>, PHP <y>  →  Đến: CI <z>, PHP <w>
- Nhánh: upgrade/php8   Baseline tag: <tag>
## Đã làm, theo phase
| Phase | Commit | Nội dung |
## Đã kiểm chứng
| Hạng mục | Lệnh | Kết quả |
## Chưa kiểm chứng
| Hạng mục | Lý do |
## Còn tồn đọng
| Việc | Mức ưu tiên | Lý do chưa làm |
## Cần người quyết định
| Vấn đề | Phương án |
## Rollback
- Tag: <tag>, image cũ: <tên>, điều kiện: <composer install offline / mirror>
```
