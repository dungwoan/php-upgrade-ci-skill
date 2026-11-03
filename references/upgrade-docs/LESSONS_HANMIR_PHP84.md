> Bundled copy from the team's upgrade-ci docs, 2026-10-29. Source of truth: the original docs folder; re-copy to refresh.

# Kinh nghiệm thực tế: nâng hanmir lên PHP 8.4

Tài liệu ghi lại những gì đã làm, những gì tài liệu cũ chưa dự đoán và các bẫy gặp phải khi
nâng `hanmir` (nhánh `uat-php84`) lên PHP 8.4 trong hai ngày 2026-10-26 và 2026-10-27.
Mục đích: để lần nâng cấp source tiếp theo không phải tìm lại từ đầu.

Đọc kèm [AI_AGENT_PLAYBOOK_PHP8.md](AI_AGENT_PLAYBOOK_PHP8.md) và
[UPGRADE_PHP.md](UPGRADE_PHP.md). Tài liệu này không thay thế playbook, chỉ bổ sung phần
thực chiến.

## 1. Phạm vi và lựa chọn đã chốt

Playbook đề xuất swap core sang fork `hoangkim28/codeigniter` (P5). Lần này **không swap
core**. Lựa chọn đã chốt:

| Hạng mục | Quyết định |
|---|---|
| Framework | Giữ CI 3.1.9 bundled trong `system/`, vá tại chỗ cho tương thích PHP 8.4 |
| Runtime | `php:8.4.27-apache`, extension cài bằng `mlocati/php-extension-installer` |
| Infra | Không đổi Dockerfile, `public/.htaccess`. `.gitlab-ci.yml` chỉ đổi theo yêu cầu deploy |
| `imap`, `soap` | Chưa cài trong lần nâng này. **Không phải vì app không dùng:** hanmir có 43 lời gọi `imap_*` (`libraries/Imap.php`, `modules/sla/models/Emailticket_model.php` nạp thư viện `imap`) và `soap` trong `modules/broadcasting/models/Sabre_model.php`. Cần xác nhận module có chạy thật, rồi cài extension (xem mục 8) |
| Composer | Không commit `composer.lock` (vẫn `composer update` lúc build) |

Lý do: swap core đụng bootstrap copy `application/core/CodeIgniter.php` (524 dòng),
`WFF_Input`, `WFF_Log`, `WFF_Security`, session driver và routes. Rủi ro lớn hơn nhiều so với
vá `system/` tại chỗ, trong khi mục tiêu trước mắt chỉ là chạy được trên 8.4.

Kết quả cuối: lint 8.4 sạch trên 1.406 file, smoke test qua 27/27 module, UAT-lab
(`https://hanmir-uat-lab.worldfone.cloud/`) chạy được và không còn lỗi PHP trên trang đăng nhập.

### Danh sách commit trên `uat-php84`

| Commit | Nội dung |
|---|---|
| `ea31fca` | Dockerfile lên `php:8.4.27-apache`, thêm job `build/deploy:uat-php84` |
| `79d22e7` | Đổi port deploy sang 8081/8444 |
| `1c19bf5` | Chuyển `wffdata.json` từ `system/config/` sang `application/config/` |
| `02aef6d` | Vá `system/` (CI 3.1.9) cho PHP 8.4 |
| `9be83e2` | Viết lại `Session_mongo_driver` |
| `5eb42fb` | `mongodb/mongodb ^2.5`, `vlucas/phpdotenv ^5.6`, pin `gears/string ^1.1.1` |
| `9ff1850` | Sửa code `application/`, `modules/` (205 file) |
| `0c8bf49`, `251c4be` | Runner tag và auto deploy (xem mục 6) |
| `c60934c` | `WFF_Log::notify_error` kiểm tra `$CI->load` |
| `b2bf7d4`, `2ef5575` | `APP_URL`, `APP_NAME` cho UAT-lab |
| `295e3e0`, `7b60034` | Đổi rồi revert `iss` của VietQR (xem mục 7) |
| `8e91ea0` | `dragonmantank/cron-expression ^3.4` |

## 2. Mười bài học quan trọng nhất

1. **Lint sạch chưa phải là chạy được.** Sau khi lint 0 lỗi, smoke test vẫn tìm ra lỗi fatal
   trên mọi request (thư viện MongoDB), mọi controller của module trả 500 (`is_callable`) và
   logout trả 500 (`delete_cookie`). Bắt buộc phải có smoke test với service thật.
2. **Extension và library phải đi cùng major version.** Dockerfile cài `ext-mongodb` mới nhất
   (2.5.5), composer lại resolve `mongodb/mongodb` 1.21.5. Kết quả: Compile Error ở
   `vendor/mongodb/mongodb/src/Model/BSONArray.php:74` trên mọi request.
3. **`composer update` không có lock là quả bom hẹn giờ.** Mỗi lần build có thể ra bộ version
   khác. Ví dụ thực tế: chỉ đổi hai constraint là composer chọn `gears/string` 0.6.0, bản này
   lỗi parse trên 8.4 vì dùng `match` làm tên hàm.
4. **Lỗi trong error handler biến deprecation thành fatal.** `WFF_Log::notify_error` gọi
   `$CI->load->is_loaded()` khi controller chưa khởi tạo xong `load`. Một dòng deprecation vô hại
   biến thành trang 500 và che mất lỗi gốc.
5. **Tài liệu cũ có thể sai về upstream.** Playbook gợi ý "mirror `#[\AllowDynamicProperties]`
   theo CI 3.1.13", nhưng 3.1.13 chính thức **không có** attribute này ở đâu cả. Phải tự thêm.
6. **Lint dừng ở lỗi parse đầu tiên của mỗi file.** `Profiler.php` báo lỗi ở dòng 108, sửa xong
   mới lộ ra cùng lỗi ở dòng 138 và 557. Sau mỗi lần sửa lỗi parse phải lint lại.
7. **Lint phải chạy với cả `short_open_tag=0` và `=1`.** Với `Off`, short tag `<?` bị in thẳng ra
   HTML mà không báo lỗi. Với `On`, dòng `<?xml` thành lỗi parse. Lint không báo lỗi cho `<?` ở
   cả hai chế độ (đã kiểm trên `php:8.4-cli`), nên view vẫn phải grep riêng.
8. **Trước khi debug code, xác nhận bản đang chạy là bản nào.** Lỗi 500 đầu tiên trên UAT-lab là
   do container còn chạy image cũ, không phải do code mới.
9. **`.env` được đóng vào image.** Đổi `APP_URL` trong git không có tác dụng cho tới khi image
   mới được build và deploy.
10. **Đừng sửa giá trị trông như "cần đổi theo môi trường" khi chưa hỏi.** JWT `iss` của VietQR
    trông giống host UAT, nhưng là giá trị cố định phía đối tác.

## 3. Những gì tài liệu cũ chưa dự đoán

### 3.1. Framework `system/` (CI 3.1.9)

| Vị trí | Vấn đề | Cách sửa |
|---|---|---|
| `system/libraries/Profiler.php:108,138,557` | `$this->_compile_{$section}` là lỗi parse trên PHP 8. Chỉ nổ khi bật profiler (`?cmd_profiler=show`) | `$this->{'_compile_'.$section}` |
| `system/core/Exceptions.php:76` | `E_STRICT` deprecated trên 8.4, gặp ở **mọi request** | Dùng literal `2048 => 'Runtime Notice'` |
| `index.php`, `public/index.php`, `application/config/Dotenv.php` | `~E_STRICT` trong `error_reporting()` | `~2048 /* E_STRICT */`, giữ nguyên giá trị hiệu lực |
| Core class (`Controller`, `Model`, `Loader`, `Router`, `URI`, `Config`, `Input`, `Output`, `Security`, `Hooks`, `Lang`, `Log`, `Utf8`, `Benchmark`, `Exceptions`, `Driver`, `DB_driver`, `Session`) | Dynamic property deprecated từ 8.2 | Thêm `#[\AllowDynamicProperties]` vào base class. Class con kế thừa attribute, nên controller và model của app không cần sửa |
| `system/libraries/Session/drivers/*` | Thiếu return type của `SessionHandlerInterface` | `#[\ReturnTypeWillChange]` trên `open/read/write/close/destroy/gc` |
| `system/libraries/Session/Session_driver.php` `_cookie_destroy()` | `setcookie(..., NULL, ...)` | Truyền `''` (giống 3.1.13) |
| `system/libraries/Session/Session.php` | `ini_set('session.sid_length')`, `sid_bits_per_character` deprecated trên 8.4 | Bỏ qua hai `ini_set` này khi `PHP_VERSION >= 8.4` |
| `system/helpers/cookie_helper.php` `delete_cookie()` | Tên cookie rỗng ném `ValueError` trên PHP 8. Với `wff_persist_session = FALSE`, logout và login sai đều trả 500 | Bỏ qua khi tên rỗng |
| `system/core/Input.php` `valid_ip()` | `$which = NULL` truyền vào `filter_var` | Mặc định `0` |
| `system/core/Security.php` | `strtoupper(config_item('charset'))` có thể nhận NULL | Ép `(string)` (giống 3.1.13) |
| `system/core/Output.php` | `$final_output` không có giá trị mặc định | `public $final_output = '';` |
| `system/libraries/{Image_lib,Table,Javascript}.php` | Thuộc tính tạo động (`dest_image`, `temp`, `CI`, `js`) | Khai báo thuộc tính |
| `system/libraries/Xmlrpcs.php:553`, `Encryption.php:371,506` | `${var}`, tham số nullable ngầm | `{$var}`, `?array` |

Không cần sửa: `system/database/drivers/mysql/*` (không dùng), `Xmlrpc.php` `strftime`
(chỉ deprecated lúc chạy, không ai gọi).

### 3.2. Application và module

| Vị trí | Vấn đề | Cách sửa |
|---|---|---|
| `application/hooks/WFF_Module.php:139` | `is_callable()` trên method non-static trả `false` từ PHP 8, nên **mọi controller của module trả 500** | Dùng `ReflectionMethod` như core |
| `application/libraries/WFF_Migration.php:306` | Cùng lỗi `is_callable`, mọi migration báo thiếu `up`/`down` | `method_exists` |
| `application/core/WFF_Log.php:97` | `$CI->load` null khi log lỗi trong lúc dựng controller | Thêm `isset($CI->load)` |
| `application/core/WFF_Log.php:114` | `utf8_encode` deprecated | `mb_convert_encoding($s, 'UTF-8', 'ISO-8859-1')` |
| `modules/broadcasting/.../Campaign_detail.php`, `ExportExcelListener.php` | `implode($array, $sep)` đảo tham số, fatal trên PHP 8 | `implode($sep, $array)` |
| `Mongo_db.php`, `Mongo_private.php`, `Mongo_secondary.php` | `"${self::class}"`, `$return_as` không khai báo, tham số optional đứng trước required | `self::class`, khai báo thuộc tính, bỏ default vô hiệu |
| 3 view `templates/popup/telesale/*` | 28 short tag `<?` | `<?php` |
| `templates/ipphone/cfg.php:1`, `modules/tool/views/bpmn_cloud_view.php:2765` | `<?xml` lỗi parse khi `short_open_tag=On` | In `<?xml` qua chuỗi PHP |
| 211 lời gọi `json_decode($this->input->post(...))` và tương tự | NULL truyền vào tham số kiểu string | `$this->input->post('x') ?? ''`. Không dùng `(string)` vì `post()` có thể trả array |
| `count()` trên giá trị có thể NULL | `TypeError` (fatal) trên PHP 8 | `count($x ?? [])`, chỉ ở chỗ thực sự có thể NULL |
| `fputcsv` (14 chỗ) | Thiếu `$escape` deprecated trên 8.4 | Truyền rõ `',', '"', '\\'` |
| `mycaptcha_helper.php` | Float truyền vào `mt_rand`, `imageline` | Ép `(int)` |
| `scandir()` trong scheduler | Trả `false` khi thư mục NAS không tồn tại, `array_diff` ném `TypeError` | `scandir($dir) ?: []` |
| `application/models/Language_model.php:25` | `strtoupper(null)` khi chưa có session | Ép `(string)` |

Với tham số optional đứng trước tham số required: PHP vốn đã bỏ qua default đó, nên xoá default
không đổi hành vi. Vẫn nên grep các nơi gọi để chắc chắn.

### 3.3. Session Mongo driver

`application/libraries/Session/drivers/Session_mongo_driver.php` cần:

- Implement thêm `SessionUpdateTimestampHandlerInterface`.
- Kiểu trả về `: bool` cho `open`, `write`, `close`, `destroy`. Giữ `#[\ReturnTypeWillChange]`
  cho `read` (có thể trả NULL) và `gc` (trả bool trong khi interface đòi `int|false`).
- `validateId($id)`: `findOne` với cùng filter như `read()`. CI 3.1.9 bật
  `session.use_strict_mode`, nên PHP sẽ gọi hàm này.
- `updateTimestamp($id, $data)`: nếu `read()` không thấy dòng hoặc ID đã đổi thì gọi `write()`,
  ngược lại chỉ `$set timestamp`.
- Khai báo `protected $_row_exists = NULL;` (NULL để giữ đúng nhánh cũ trong `write()`).

Không copy nguyên bản của jaccs vì bản đó dựa vào core của fork và các thành phần chỉ jaccs có.

### 3.4. Composer và extension

| Package | Trước | Sau | Lý do |
|---|---|---|---|
| `mongodb/mongodb` | `^1.4` → 1.21.5 | `^2.5` → 2.5.0 | Bắt buộc khi dùng `ext-mongodb` 2.x |
| `vlucas/phpdotenv` | 4.3.0 | `^5.6` → 5.8.0 | v4 phát deprecation nullable ở mọi request |
| `gears/string` | không khai báo | `^1.1.1` | Ngăn composer chọn 0.6.0 (lỗi parse trên 8.4) |
| `dragonmantank/cron-expression` | `^1.2` → 1.2.1 | `^3.4` → 3.6.1 | v1 phát deprecation `$fieldFactory` ở mỗi lần chạy `cli/schedule/run` |

Thay đổi API phải sửa kèm:

- **ext-mongodb 2.x:**
  - `Manager::executeQuery/executeBulkWrite/executeCommand` không nhận object ở tham số thứ ba
    nữa. Phải truyền `['readPreference' => ...]` hoặc `['writeConcern' => ...]` (28 chỗ).
    Lần sửa đầu bỏ sót `Mongo_secondary::command()` (`application/libraries/Mongo_secondary.php:1851`),
    gây lỗi `{"status":0,"message":"Expected options to be array, MongoDB\\Driver\\ReadPreference given"}`
    ở API monitor `overview()`. Đã sửa ở commit `550698f`. Bài học: khi đổi một kiểu gọi API ra nhiều
    file, grep toàn bộ call site, kể cả hàm ít dùng như `command()`, `aggregate()`, đừng chỉ dựa vào
    các hàm chính.
  - `new ReadPreference('RP_PRIMARY')` ném `Invalid mode`. Dùng chuỗi `'primary'`.
  - `new UTCDateTime(float)` ném lỗi. Dùng `(int) round($stamp * 1000)`.
- **phpdotenv v5:** `createImmutable` không còn ghi vào `getenv()`. Code đọc biến môi trường qua
  `getenv()` thì phải dùng `Dotenv::createUnsafeImmutable`, nếu không mọi `env()` trả rỗng.
- **cron-expression v3:** `CronExpression::factory()` vẫn chạy nhưng đã `@deprecated`. Nên
  chuyển sang `new CronExpression(...)` khi dọn dẹp.

Vendor vẫn còn khoảng 75 file phát deprecation nullable ngầm khi lint (symfony, predis 1.x,
dompdf 0.8.6, phpword, google/apiclient), nhưng không file nào bị gọi trong các luồng đã smoke
test. `gears/pdf`, `gears/string` kéo theo `icecave/repr` có cú pháp `$value{$index}` đã bị gỡ;
app không dùng hai package này và nên gỡ khỏi `composer.json`.

## 4. Kiểm tra bằng Docker (máy dev không cài PHP)

### 4.1. Lint

Script lint một file, bỏ qua exit code để `xargs` không dừng giữa chừng:

```sh
#!/bin/sh
# lintone.sh <file> — in ra mọi dòng Parse/Fatal/Deprecated/Warning
php -d short_open_tag="${SOT:-0}" -d error_reporting=-1 -d display_errors=1 -l "$1" 2>&1 \
  | grep -E 'Parse error|Fatal error|Deprecated|Warning' || true
```

```sh
for sot in 0 1; do
  docker run --rm -e SOT=$sot -v /tmp/lintone.sh:/lintone.sh:ro -v "$PWD":/app:ro php:8.4-cli \
    sh -c 'cd /app; find application modules cronjob cron index.php public/index.php system \
      \( -path public/proui -o -path public/kendoui \) -prune -o -name "*.php" -print0 \
      | xargs -0 -n1 -P8 /lintone.sh'
done
```

Kết quả rỗng là sạch. Nên cài một file lỗi cố ý để chắc chắn script thực sự báo lỗi.

### 4.2. Smoke test

Lint không bắt được lỗi phụ thuộc dữ liệu (NULL vào hàm string, `count(null)`, `ValueError`).
Cách đã dùng:

1. Copy repo ra `/tmp/hcopy`, không chạy trong repo thật.
2. Build image từ chính Dockerfile của repo, chạy `composer update` y như lúc build.
3. Tạo một Docker network, chạy `mongo:7`, `redis:7`, `memcached`, `beanstalkd`. Sửa `.env`
   **trong bản copy** cho trỏ vào các container này.
4. Chạy với `-d error_reporting=-1 -d display_errors=1`:
   - CLI: `php index.php cli schedule run`, `cli queue priority|reload|work`, `cli queue single runCommand`.
   - Web: Apache trong image, curl `/`, `/action/login` và mọi controller API.
5. Seed một user (cần `extension` khác rỗng và `role_id` trong cả `_worldfone4xs.User` lẫn
   `worldfone4xs.User`), lấy captcha từ collection `worldfone4xs.Captcha`, đăng nhập rồi gọi các
   API khi đã xác thực.
6. Lọc output theo `Deprecated|Warning|Fatal|TypeError|ValueError|ArgumentCountError`, tách riêng
   lỗi trong `vendor/`.

Độ phủ đạt được: 304 request GET có xác thực trên 27 module, 57/57 view, 23 lần chạy cron,
export CSV và Excel. Không có Oracle và không gọi được các host OMNI, nên các luồng đó vẫn phải
test trên UAT.

## 5. Bảng tra nhanh: triệu chứng → nguyên nhân

| Triệu chứng | Nguyên nhân | Xem |
|---|---|---|
| Mọi request 500, `Call to a member function is_loaded() on null` ở `WFF_Log.php:97` | Một deprecation khi dựng controller, rồi `notify_error` sập | 3.2 |
| Mọi request 500, Compile Error ở `vendor/mongodb/mongodb/src/Model/BSONArray.php` | `ext-mongodb` 2.x với `mongodb/mongodb` 1.x | 3.4 |
| Mọi controller của module 500, controller `application/` vẫn chạy | `is_callable` trong `WFF_Module` | 3.2 |
| Logout hoặc đăng nhập sai trả 500 | `delete_cookie('')` ném `ValueError` | 3.1 |
| `env()` trả rỗng, `base_url` rỗng | phpdotenv v5 dùng `createImmutable` | 3.4 |
| `Invalid mode` khi tạo `ReadPreference` | ext-mongodb 2.x chỉ nhận chuỗi | 3.4 |
| Trang hiện nguyên văn `<? echo ... ?>` | Short tag với `short_open_tag=Off` | 3.2 |
| Trang lỗi chứa `E_STRICT` dù code đã sửa | Container vẫn chạy image cũ | 6 |
| Redirect sang host cũ dù `.env` đã đổi | `.env` đóng trong image cũ | 6 |
| JSON API lẫn chữ `Deprecated:` | `public/.htaccess` đặt `CI_ENV development`, `display_errors on`; `index.php` gọi `error_reporting(-1)` | 6 |
| Mongo ghi lỗi severity 8192 từ `CronExpression.php:69` | `dragonmantank/cron-expression` 1.x | 3.4 |

## 6. Bẫy CI/CD và deploy

- **Xác định bản đang chạy trước khi debug.** Cách đã dùng khi không có SSH:
  - So nội dung trang lỗi với code ở từng commit. Trang lỗi trên UAT báo `E_STRICT` ở
    `Exceptions.php:75`, đúng dòng của commit cũ.
  - Chạy lại code commit cũ trên local với `.env` thật: trang lỗi giống hệt từng ký tự.
  - Gửi các `Host` header khác nhau thẳng vào `IP:port` của container. Kết quả không đổi theo
    `Host` thì không phải do proxy.
  - Khi có SSH: `docker inspect <container> --format '{{.Config.Image}}'`.
- **Image gắn tag theo commit** (`php84-$CI_COMMIT_SHORT_SHA`). Job deploy `when: manual` chỉ
  deploy image của pipeline mà nó thuộc về. Chạy lại job của pipeline cũ là deploy lại bản cũ.
- **Runner tag phải có runner online.** Đổi tag sang `uat-php84` khi chưa có runner mang tag đó
  làm pipeline treo ở trạng thái pending, không báo lỗi gì. Hiện chỉ runner `uat-old` chạy.
- **Bỏ `when: manual` thì mỗi lần push là một lần deploy.** Cần xác nhận trước khi push.
  Deploy mất khoảng 14 phút, có một khoảng ngắn trả 502 khi đổi container.
- **Tên container.** Job `uat-php84` từng dùng chung tên `4xs_webportal_hanmir` với job `uat`,
  nên deploy bản này sẽ xoá container UAT cũ. Đã đổi thành `4xs_webportal_hanmir-uat-php84`.
- **`.env` và `wffdata.json` được commit và đóng vào image.** Đổi host phải build lại image.
  Nên truyền `APP_URL` bằng `docker run -e`. `createUnsafeImmutable` không ghi đè biến đã có sẵn
  nên biến truyền vào sẽ thắng.
- **Ẩn deprecation trong `zz-custom.ini` không đủ.** `public/.htaccess` và `public/index.php` ghi
  đè lại cấu hình này ở môi trường `development`. `application/config/Dotenv.php` cũng có
  `error_reporting` riêng (mục 3.1). Tìm mọi chỗ bật tắt lỗi, không chỉ một.

## 7. Quy tắc làm việc rút ra

- Hỏi trước khi đổi infra (Dockerfile, CI, `.htaccess`, `.gitignore`) và trước mỗi lần push khi
  push kéo theo deploy.
- Không tự đổi giá trị cố định với đối tác (JWT `iss`, callback URL, key) chỉ vì thấy chứa tên
  host. Báo lại và hỏi.
- Vá lỗi trong vendor bằng cách nâng version trong `composer.json`, không sửa trực tiếp
  `vendor/`.
- Mỗi lớp sửa nên là một commit riêng (di chuyển file, `system/`, session driver, composer,
  application), message theo kiểu repo: `fix(php84): ...`, không dấu.
- Secret đã nằm trong lịch sử git (`.env`, `wffdata.json`, cấu hình Oracle) thì báo để đổi key,
  không rewrite history.

## 8. Việc còn tồn

| Việc | Ghi chú |
|---|---|
| 43 API trả 500 khi gọi thiếu tham số | `ArgumentCountError`, chủ yếu `popup/api/v1/Card/*` và `*/detail` không có id |
| API trả dữ liệu khi chưa đăng nhập | `/api/restful/config`, `cdr`, `file`; 29 route của `application/` trả 200 khi không có session |
| Cảnh báo truy cập phần tử của NULL | Khoảng 34 chỗ offset và 9 chỗ `foreach` trên NULL khi dữ liệu rỗng |
| Gỡ `gears/pdf`, `gears/string` | App không dùng, kéo theo package lỗi parse trên 8.4 |
| Commit `composer.lock`, đặt `"php": "^8.4"` | Hiện mỗi lần build có thể ra version khác |
| `.env` UAT bật hiển thị lỗi | `APP_ENV=development`, `display_errors` on |
| Test với Oracle, OMNI và dữ liệu thật | Chưa phủ được ở local |
| Deploy `550698f` và test `wfpbx/api/v1/cdr` bằng session trên UAT-lab | Chưa xác nhận: lần push cuối bị gián đoạn. Cần kiểm tra `origin/uat-php84` có `550698f` chưa, rồi chạy lại việc deploy và test |
| Swap core sang fork (P5 của playbook) | Chưa làm; xem [AI_AGENT_PLAYBOOK_PHP8.md](AI_AGENT_PLAYBOOK_PHP8.md) |
| `imap`, `soap` chưa cài | Xác nhận module `sla` (Emailticket) và `broadcasting` (Sabre) có chạy thật. Nếu có, cài `imap` (PECL từ PHP 8.4, xem [UPGRADE_PHP.md](UPGRADE_PHP.md) mục 3.6) và `soap` |

## 9. Checklist rút gọn cho source tiếp theo

1. Đối chiếu major version: `ext-mongodb` với `mongodb/mongodb`, các package dùng API đã đổi.
2. Lint 8.4 với `short_open_tag` 0 và 1, lặp lại sau mỗi lần sửa lỗi parse. Gate phải fail trên output, không chỉ exit code: `php -l` thoát 0 khi file chỉ có `Deprecated`.
3. Grep: `implode(` đảo tham số, `${`, `utf8_encode`, `E_STRICT`, `is_callable(` với method
   non-static, `fputcsv(`, `delete_cookie(`, `json_decode($this->input->`, `count(`.
4. Thêm `#[\AllowDynamicProperties]` vào base class của framework, không đợi upstream.
5. Kiểm tra error handler và logger: chúng không được sập khi `get_instance()` chưa đầy đủ.
6. Smoke test với service thật: CLI, web không xác thực, web có xác thực, export.
7. Kiểm tra pipeline: runner tag có runner online, tên container không trùng, image tag đúng
   commit vừa push.
8. Sau deploy: xác nhận container chạy đúng image trước khi đọc lỗi.
