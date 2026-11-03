> Bundled copy from the team's upgrade-ci docs, 2026-10-29. Source of truth: the original docs folder; re-copy to refresh.

# Nâng cấp PHP cho codebase CodeIgniter (5.6 → 8.x)

Tài liệu bổ sung cho `UPGRADE_FROM_2.2.6.md` và `UPGRADE_FROM_3.1.13.md`. Hai tài liệu đó xử lý phần framework; tài liệu này xử lý phần **ngôn ngữ và runtime**.

Dữ liệu thực tế lấy từ hai codebase nội bộ: `<path>/jaccs` (đã nâng xong, PHP 8.5) và `<path>/hanmir` (chưa nâng, PHP 7.x). So sánh chi tiết hai source nằm ở `COMPARE_JACCS_HANMIR.md`.

## 1. Chọn phiên bản đích

| Phiên bản | Trạng thái hỗ trợ | Khuyến nghị |
|---|---|---|
| 5.6 và thấp hơn | Hết hỗ trợ từ 2018 | Không dùng |
| 7.0 - 7.4 | Hết hỗ trợ từ 2022 | Không dùng |
| 8.0 - 8.2 | Hết security support | Chỉ dùng làm bậc trung gian |
| **8.3** | Còn security support | Bậc trung gian an toàn |
| **8.4** | Active support | **Đích tối thiểu** |
| **8.5** | Active support | Đích khuyến nghị nếu dependency cho phép |
| 8.6 trở lên | Chưa khả dụng cho stack hiện tại | `phpoffice/phpspreadsheet` 2.4.7 yêu cầu `<8.6.0`, nên 8.5 là trần hiện tại |

jaccs đang chạy PHP 8.5 với `composer.json` khai báo `"php": "^8.4"`. Giữ nguyên quy ước này cho hanmir: khai báo `^8.4`, chạy 8.5.

Fork `hoangkim28/codeigniter` (repo: <https://github.com/hoangkim28/codeigniter>) khai báo `>=5.4.8` và tài liệu của nó khuyến nghị 8.4+. Ràng buộc thực tế đến từ package của ứng dụng, không đến từ framework.

## 2. Thứ tự nâng cấp

Không nâng framework và PHP trong cùng một lần deploy. Thứ tự đã được jaccs kiểm chứng:

```
Bước 0  Chốt baseline: tag/commit hiện tại chạy ổn trên PHP cũ
Bước 1  Sinh composer.lock, nâng package lên bản hỗ trợ PHP 8  (vẫn chạy PHP cũ)
Bước 2  Sửa lỗi cú pháp và hàm đã bị gỡ                          (vẫn chạy PHP cũ)
Bước 3  Nâng PHP lên 8.3 ở môi trường dev                        (framework chưa đổi)
Bước 4  Dọn deprecation của 8.0 → 8.3
Bước 5  Nâng framework lên fork 3.4.5                            (xem UPGRADE_FROM_*.md)
Bước 6  Nâng PHP lên 8.4 rồi 8.5
Bước 7  Dọn deprecation của 8.4 và 8.5, xử lý extension đã chuyển sang PECL
```

Lý do tách: CI 3.1.x **không** chạy sạch trên PHP 8.x (thiếu `#[AllowDynamicProperties]`, `Session` chưa có wrapper cho `SessionHandlerInterface` kiểu mới). Nên bước 3 chỉ nhằm phát hiện lỗi tầng ứng dụng, chạy ở dev, không deploy. Việc chạy production trên PHP 8 chỉ bắt đầu sau bước 5.

Trường hợp codebase đang ở CI 2.2.6: làm `UPGRADE_FROM_2.2.6.md` trước toàn bộ, vì CI 2.x phụ thuộc `mysql_*` vốn đã bị gỡ từ PHP 7.

## 3. Danh mục breaking change theo phiên bản

### 3.1 PHP 7.0 - 7.4 (nếu xuất phát từ 5.6)

| Thay đổi | Phiên bản | Cách sửa |
|---|---|---|
| Gỡ toàn bộ `mysql_*` | 7.0 | Chuyển `dbdriver` sang `mysqli`, thay mọi lời gọi `mysql_*` trực tiếp trên `$this->db->conn_id` |
| Gỡ `ereg*`, `split()`, `/e` của `preg_replace` | 7.0 | Dùng `preg_*`, `preg_split`, `preg_replace_callback` |
| Constructor kiểu PHP 4 bị deprecated rồi gỡ | 7.0 / 8.0 | Đổi `function TenClass()` thành `__construct()` |
| Gỡ `$HTTP_RAW_POST_DATA` | 7.0 | `file_get_contents('php://input')` |
| `list()` không còn gán được string offset | 7.0 | Dùng `str_split()` |
| Gỡ `mcrypt_*` | 7.2 | Dùng `openssl_*`, hoặc library Encryption của CI |
| `each()` deprecated | 7.2 | `foreach` |
| `create_function()` deprecated | 7.2 | Closure |
| `get_magic_quotes_gpc()` deprecated | 7.4 | Xóa, magic quotes đã bị gỡ từ 5.4 |
| `{}` truy cập ký tự chuỗi deprecated | 7.4 | `$s[0]` |

### 3.2 PHP 8.0 — nhóm gây fatal

Đây là nhóm phải sửa trước khi bật PHP 8, vì nó ném exception chứ không chỉ cảnh báo.

| Thay đổi | Hậu quả | Cách sửa |
|---|---|---|
| `implode($array, $glue)` thứ tự cũ bị gỡ | `TypeError` | Đổi thành `implode($glue, $array)` |
| Truyền NULL vào tham số internal không nullable | `TypeError` ở nhiều hàm, `count(null)` là ví dụ điển hình | Ép kiểu `(string)`, thêm `?? ''`, hoặc guard `is_array()` trước `count()` |
| Gỡ `create_function()`, `each()`, `money_format()`, `get_magic_quotes_gpc()`, `ereg*`, `split()`, `mcrypt_*`, `__autoload()` | Fatal "undefined function" | Thay như bảng 3.1 |
| Constructor kiểu PHP 4 bị gỡ hẳn | Không còn được coi là constructor | Đổi sang `__construct()` |
| Gỡ cú pháp `{}` cho string offset | Parse error | `$s[0]` |
| `assert()` với tham số chuỗi bị gỡ | Fatal | Truyền biểu thức |
| Tham số bắt buộc đứng sau tham số có default | Deprecated (8.0), nên sửa ngay | Bỏ default của tham số trước, hoặc đổi thứ tự |
| So sánh chuỗi với số đổi ngữ nghĩa | `0 == "abc"` nay là `false` | Rà soát so sánh lỏng giữa input và số |
| `@` không còn chặn fatal error | Lỗi vốn bị giấu nay lộ ra | Xử lý lỗi tường minh |

### 3.3 PHP 8.1

| Thay đổi | Mức độ | Cách sửa |
|---|---|---|
| Truyền NULL vào tham số internal không nullable | Deprecated, sẽ fatal ở bản sau | Ép kiểu hoặc `??` |
| Interface `Serializable` deprecated | Deprecated | Dùng `__serialize()` / `__unserialize()` |
| Method của interface nội bộ cần khai báo kiểu trả về | Deprecated | Thêm `#[\ReturnTypeWillChange]` hoặc khai báo kiểu thật. Áp dụng cho class implement `ArrayAccess`, `Iterator`, `IteratorAggregate`, `Countable`, `JsonSerializable`, `SessionHandlerInterface` |
| `strftime()`, `gmstrftime()` deprecated | Deprecated | `IntlDateFormatter` hoặc `date()` |
| `date_sunrise()`, `date_sunset()` deprecated | Deprecated | `date_sun_info()` |
| `FILTER_SANITIZE_STRING` deprecated | Deprecated | `htmlspecialchars()` |
| Resource đổi thành object ở nhiều extension | Thay đổi hành vi, không cảnh báo | `imap_open` trả về `IMAP\Connection`, `curl_init` trả về `CurlHandle`. Mọi `is_resource()` trên các giá trị này đều trả `false`. Đổi sang `instanceof` hoặc `!== false` |
| `$GLOBALS` không còn ghi đè toàn phần | Hiếm gặp | Gán theo từng key |

### 3.4 PHP 8.2

| Thay đổi | Mức độ | Cách sửa |
|---|---|---|
| Dynamic property deprecated | Deprecated, sẽ fatal ở 9.0 | Khai báo property, hoặc gắn `#[\AllowDynamicProperties]` lên class |
| Nội suy `${var}` trong chuỗi deprecated | Deprecated | `{$var}` |
| `utf8_encode()`, `utf8_decode()` deprecated | Deprecated | `mb_convert_encoding($s, 'UTF-8', 'ISO-8859-1')` |
| `${self::class}` không còn hợp lệ | Deprecated | Dùng `self::class` tách khỏi chuỗi |
| Callable dạng chuỗi một phần bị gỡ | Fatal | Dùng mảng `[$obj, 'method']` hoặc first-class callable |

Lưu ý riêng cho CodeIgniter: fork 3.4.5 gắn `#[AllowDynamicProperties]` cho `CI_Controller`, `CI_Model`, `CI_Loader`, `CI_DB_driver`, `CI_Driver_Library`. **Không** gắn cho `CI_Router`, `CI_Config`, `CI_Session`, `CI_Driver`, `CI_Profiler`. Code nào set property động lên nhóm sau sẽ sinh deprecation.

### 3.5 PHP 8.3

| Thay đổi | Mức độ | Cách sửa |
|---|---|---|
| `ReflectionClass::getStaticProperties()` đổi hành vi | Thấp | Hiếm dùng trong CI |
| Hằng số class có thể khai báo kiểu | Tính năng mới | Không bắt buộc |
| `range()` siết kiểu tham số | Cảnh báo | Truyền số đúng kiểu |

8.3 là bậc nâng cấp nhẹ nhất; dùng nó làm chốt kiểm tra trung gian.

### 3.6 PHP 8.4

| Thay đổi | Mức độ | Cách sửa |
|---|---|---|
| **Extension `imap` chuyển khỏi core sang PECL** | Chặn | Cài `pecl install imap`, hoặc gói distro tương ứng, ví dụ `php85-pecl-imap` trên Alpine |
| Nullable ngầm trong khai báo tham số deprecated | Deprecated | `function f(Foo $x = null)` đổi thành `function f(?Foo $x = null)` |
| `E_STRICT` không còn ý nghĩa | Deprecated (không fatal) khi code còn tham chiếu hằng số này. Lint không báo, phải grep | Bỏ khỏi `error_reporting()`; fork 3.4.5 đã xử lý trong `Exceptions.php`, nhưng `index.php` tự viết thì phải sửa tay |
| `session.sid_length` đổi cách xử lý | Thay đổi hành vi | Fork đã bỏ qua việc chỉnh sid length trên 8.4+ |
| Một số hàm `mysqli` đổi tham số | Thấp | Dùng `mysqli` qua CI driver |

### 3.7 PHP 8.5

| Thay đổi | Mức độ | Cách sửa |
|---|---|---|
| `curl_close()` deprecated | Deprecated | Xóa lời gọi; handle tự giải phóng. Lint không báo, phải grep `curl_close(` |
| Ép kiểu không chuẩn `(double)`, `(boolean)`, `(integer)`, `(binary)` | Deprecated | `(float)`, `(bool)`, `(int)`, `(string)`. Lint báo với `(double)` (đã kiểm trên `php:8.5-cli`); các cast còn lại đã thấy deprecated khi chạy |
| Đọc trực tiếp `$http_response_header` | Deprecated | `http_get_last_response_headers()`. Lint báo (đã kiểm) |
| Một số hằng số và hàm cũ bị gỡ tiếp | Thấp | Chạy lint để phát hiện |

jaccs đã gỡ toàn bộ 34 lời gọi `curl_close()` khi lên 8.5. hanmir có 165 lời gọi `curl_*`, cần rà lại khi tới bước này.

## 4. Hiện trạng của hai codebase

### 4.1 Bảng đối chiếu

| Tiêu chí | jaccs | hanmir |
|---|---|---|
| `composer.json` require php | `^8.4` | `>=5.6.4` |
| Runtime | PHP 8.5 trên Alpine 3.24 | PHP 7.x, image `hub.southtelecom.vn/php7-oci-kafka` |
| `php -l` toàn bộ app | Sạch trên 8.3.33, 8.4.27, 8.5.12 | Chưa chạy được |
| Số file đã quét | 1231 `application`, 177 `cronjob`, 75 `public`, 61 `tests`, 2 root | 577 file PHP chỉ riêng `modules/` |
| Lỗi nhóm fatal còn lại | 6 | trên 230 |
| Lỗi nhóm deprecated còn lại | 7 | trên 250 |

Tín hiệu mâu thuẫn ở hanmir cần lưu ý: code **đã** gọi hàm chỉ có trên PHP 8 tại `application/controllers/api/restful/Cron.php:49,87`, `modules/vietqr/controllers/api/v1/Bank.php:24` và `modules/payment/controllers/Webhook.php:77`. Các nhánh này sẽ fatal trên PHP 7, nghĩa là hoặc chúng chưa từng chạy, hoặc runtime thật đã khác tên image. Xác minh bằng `php -v` trong container trước khi lập kế hoạch.

### 4.2 Lỗi còn lại của jaccs

| Lỗi | Số lượng | Vị trí |
|---|---|---|
| `implode()` đảo tham số | 5 | `cronjob/Mongo_private.php:1923`, `cronjob/console/app/Libraries/Mongo_db.php:1937`, `cronjob/LOAN/report/mini_processes/Mongo_db_process.php:1939`, `cronjob/LOAN/report/model/Mongo_db_report.php:1939`, `cronjob/LOAN/cron_don_dep/Mongo_db.php:1925` |
| `get_magic_quotes_gpc()` | 1 | `public/proui/js/helpers/ckeditor/samples/old/assets/posteddata.php:35` — xóa file sample |
| Truyền NULL vào hàm internal | 7 | `api/report/loan/List_of_overdue_report.php:21`, `api/v1/Ticket.php:173`, `api/report/loan/Working_date_report.php:67`, `Working_date_partner_report.php:67`, `api/v1/Model.php:32-33` |
| Dynamic property | 1 class | `libraries/Googleplus.php:17,26` — code chết, nên xóa |
| Thiếu extension trong image | 2 | `ftp` (`models/Ftp_model.php:20,22`, `controllers/api/report/Server.php`, `cronjob/agent_state_lock.php`) và `imap` (`libraries/Imap.php` dùng bởi `Emailticket_model.php:185`, `controllers/api/wf4x/Test.php:13`) |

Bản copy trong `application/libraries` đã được sửa; chỉ còn các bản sao trong `cronjob/` chưa đồng bộ. Đây là hệ quả của việc duy trì 6 bản `Mongo_db`/`Mongo_private` song song — nên gộp về một nguồn.

Rủi ro cấu hình: `index.php` của jaccs đặt `error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT)` cho production và testing, tức **mọi deprecation của PHP 8 đều bị giấu**. Khi nâng lên bản PHP kế tiếp, tạm bật đầy đủ ở môi trường staging để thấy cảnh báo.

### 4.3 Lỗi của hanmir, theo nhóm

Toàn bộ con số là **cận dưới**, lấy từ quét tĩnh (không có PHP binary trên máy phân tích).

| Nhóm | Số lượng | Vị trí tiêu biểu | Cách sửa |
|---|---|---|---|
| `implode()` đảo tham số (fatal 8.0) | 6 | `modules/broadcasting/controllers/api/v1/Campaign_detail.php:152,159,166`; `modules/broadcasting/models/Listeners/ExportExcelListener.php:28,35,42` | `implode(';', $arr)` |
| Tham số bắt buộc sau tham số có default | 17 | 7 mỗi file ở `Mongo_db.php`, `Mongo_private.php`, `Mongo_secondary.php` (`where_gt`, `where_gte`, `where_lt`, `where_lte`, `where_between`, `where_between_ne`, `where_ne` dạng `($field="", $x[, $y])`); 2 ở `models/Pbx_model.php`; 1 ở `modules/phone_not_call/.../Phone_Not_Call.php` | Bỏ default của `$field` |
| Nội suy `${var}` (8.2) | 7 | `controllers/api/v1/Changelog.php:172`; `libraries/Mongo_db.php:62`; `Mongo_private.php:62`; `Mongo_secondary.php:62`; `libraries/Session/drivers/Session_mongo_driver.php:44`; `modules/customer_basket_co/controllers/scheduler/ProcessFolder.php:282`; `modules/customer_basket_co/controllers/api/v1/GetData.php:243` | `{$ext}`; riêng `${self::class}` đổi thành `self::class` |
| `utf8_encode()` (8.2) | 2 | `libraries/Imap.php:1279`; `core/WFF_Log.php:114` | `mb_convert_encoding($s, 'UTF-8', 'ISO-8859-1')` |
| `is_resource()` trên object (8.1) | 3 | `libraries/Imap.php:119,199,1443` | `$this->stream instanceof \IMAP\Connection` |
| Short tag `<?` | 28 trong 3 view | `views/templates/popup/telesale/return_pool.php` (10); `popup_dynamic.php` (10); `popup_dynamic_bk.php` (8) | Đổi sang `<?php`. Fork đã bỏ `rewrite_short_tags` nên không còn cứu được bằng config |
| Dynamic property (8.2) | 4 vị trí | `hooks/WFF_Module.php:42` (`$module_path`), `:113` (`CI_Router::$module`); `Session_mongo_driver.php:176-192` (`$_row_exists`); `third_party/WClosure.php` (`reference`, `scope`) | Khai báo property. `CI_Router` không có `#[AllowDynamicProperties]` nên bắt buộc đổi cách lưu |
| Truyền NULL vào hàm internal (8.1) | trên 210 | 204 là `json_decode($this->input->post(...))`; còn lại là `strtoupper`, `urldecode`, `base64_decode`, `htmlspecialchars`. Nhiều nhất: `modules/monitor/controllers/api/v1/Monitor.php` (6), `modules/sla/controllers/api/v1/Ticket.php` (5), `modules/tool/controllers/api/v1/Library.php` và `Call_script.php` (4 mỗi file) | `json_decode((string) $this->input->post('x'))` hoặc `?? ''` |
| `count()` / `sizeof()` cần rà | 358 | Rải khắp | `count(null)` là `TypeError` trên 8.0. Guard `is_array() || $x instanceof Countable` |
| `$HTTP_RAW_POST_DATA` | 1 | `application/core/CodeIgniter.php:105`, nằm trong block chết `!is_php('5.4')` | Xóa khi rebase bootstrap |
| `unserialize()` không giới hạn class | 8 | `Broadcast_redis.php:80`; `Broadcast_log.php:83`; `Cache_rediscluster.php:144`; `Cache_mongodb.php:82`; `Popup_co_model.php:28,64`; `PromiseListener.php:54`; `common_helper.php:317` | Không phải lỗi PHP 8, nhưng nên thêm `['allowed_classes' => false]` |
| Interface `Serializable` (8.1) | 1 | `third_party/WClosure.php` qua `opis/closure` 3.x | Chuyển sang `laravel/serializable-closure` |

Nhóm **không** có lỗi nào ở hanmir, đã kiểm tra và loại hết false positive: `mysql_*`, `ereg*`, `split()`, `each()`, `money_format()`, `get_magic_quotes_gpc()` trong code ứng dụng, `mcrypt_*` trong code ứng dụng, `__autoload()`, constructor kiểu PHP 4 trong code ứng dụng, `{}` string offset, `assert(string)`, `strftime`, `date_sunrise`, `FILTER_SANITIZE_STRING`.

`application/third_party/phpseclib` 1.0.x có 2 lời gọi `create_function` (`Base.php:2558`, `X509.php:3004`), 35 lời gọi `mcrypt_*` và 14 constructor kiểu PHP 4, nhưng tất cả đều nằm sau guard `version_compare` hoặc `function_exists`, nên không chạm trên PHP 8. Vẫn nên thay bằng `phpseclib/phpseclib` v3 vì bản 1.x không còn được bảo trì.

## 5. Extension và runtime

### 5.1 Ma trận extension

| Extension | jaccs dùng | hanmir dùng | Ghi chú |
|---|---|---|---|
| `mongodb` | Có | Có | PECL. jaccs cài `php85-pecl-mongodb ~2.3.3`. Library `mongodb/mongodb` phải từ 1.15 trở lên cho PHP 8.1-8.4, ext 1.21 cho 8.4 |
| `memcached` | Có | Không | PECL |
| `redis` | Không | Có | PECL |
| `rdkafka` | Không | Có | PECL, phải build vào image mới |
| `oci8` | Không | Có | PECL, cần Oracle Instant Client trong image |
| `imap` | Có, **thiếu trong image** | Có (43 lời gọi) | **Chuyển sang PECL từ PHP 8.4** |
| `ftp` | Có, **thiếu trong image** | Không | Gói `php85-ftp` trên Alpine |
| `soap` | Không | Có (`modules/broadcasting/models/Sabre_model.php:37,110,136`) | |
| `gd` | Có | Có (18 lời gọi) | |
| `curl` | Có | Có (165 lời gọi) | |
| `openssl`, `mbstring`, `iconv`, `intl`, `zip`, `xml*` | Có | Có | Thường có sẵn |
| `mcrypt` | Không | Không (chỉ trong code có guard) | Đã gỡ từ PHP 7.2, không cài lại |

Việc cần làm ngay cho jaccs: thêm `php85-ftp` và `php85-pecl-imap` vào `docker/Dockerfile.base`, rồi xác nhận bằng `php -m` trong image đã build. Hiện code gọi `ftp_connect` và `imap_open` nhưng image không có extension, nên các tính năng này đang hỏng âm thầm.

Lưu ý: image `php:8.4-cli` chính thức không có `ftp` (đã kiểm: `function_exists('ftp_connect')` là false). Image nào có code gọi `ftp_*` đều phải cài extension này. Ngược lại, `imap` chỉ cần khi có code gọi: namabank cài `imap` nhưng không có nơi nào nạp thư viện `Imap` (xem `LESSONS_NAMABANK_PHP84.md` mục 3.4).

### 5.2 Web server

hanmir đang chạy Apache với mod_php. Khi chuyển sang PHP 8 qua php-fpm, các directive `php_flag` và `php_value` trong `.htaccess` sẽ gây **HTTP 500**, vì chúng chỉ hợp lệ dưới mod_php. Các dòng hiện có trong `.htaccess` của hanmir: `display_errors on`, `memory_limit -1`, `max_execution_time 0`, `post_max_size 0`, `error_log /var/www/html/worldfone4xs/PHP_errors.log` (đường dẫn không tồn tại).

Cách xử lý: chuyển các giá trị này vào `php.ini` hoặc pool config của php-fpm. Về `SetEnv CI_ENV development`: chỉ bỏ khi không có code nào đọc hay ghi nó. Nếu có công cụ ghi lại dòng này (namabank: `api/v1/Config.php` đổi theo môi trường DEV/UAT/LIVE), xóa dòng sẽ làm hỏng chức năng đó. Khi đó, quyết định hiển thị lỗi phải dựa vào `display_errors` và cờ như `APP_DEBUG`, không dựa vào `CI_ENV`.

jaccs đã đi qua bước này: `docker/nginx-default.conf` chỉ cho `index.php` và `ping.php` chạy PHP, các `.php` khác trả 404. Dùng cấu hình đó làm mẫu, có điều chỉnh cho đường dẫn `upload/` của hanmir.

## 6. Công cụ kiểm tra

| Công cụ | Dùng để | Lệnh mẫu |
|---|---|---|
| `php -l` | Bắt lỗi cú pháp và deprecation ở thời điểm compile | `find application -name '*.php' -print0 \| xargs -0 -n1 php -d error_reporting=-1 -d display_errors=1 -l` |
| Docker image PHP | Lint chéo nhiều phiên bản mà không cần cài lên host | `docker run --rm -v "$PWD":/app:ro php:8.4-cli php -l /app/index.php` |
| PHPCompatibility (PHP_CodeSniffer) | Quét theo phiên bản đích, bắt được nhiều thứ `php -l` bỏ sót | `phpcs -p . --standard=PHPCompatibility --runtime-set testVersion 8.4-` |
| Rector | Tự động sửa phần lớn nhóm cú pháp, dùng set `LevelSetList::UP_TO_PHP_84` | Chạy trên nhánh riêng, review từng commit |
| PHPStan | Bắt lỗi logic và kiểu, cần bootstrap riêng cho CI | Bắt đầu từ level 0, tăng dần |
| `composer validate` và `composer audit` | Kiểm tra manifest và lỗ hổng đã công bố | Thêm vào pipeline |

jaccs đã chạy `php -l` toàn bộ trên ba phiên bản 8.3.33, 8.4.27, 8.5.12 qua Docker và cho kết quả sạch. Đây là mức kiểm tra tối thiểu, **không** bắt được lỗi runtime: truyền NULL vào hàm internal, `count()` trên giá trị không đếm được, so sánh `0 == "abc"`, truy cập mảng trên `null` hoặc `false`, phép `+=` trên chuỗi, gọi static vào method non-static. Những lỗi này chỉ lộ ra khi chạy thật. Riêng `php -l` thoát mã 0 khi file chỉ có `Deprecated` (đã kiểm trên `php:8.4-cli`), nên gate phải đọc output, không chỉ exit code.

Pipeline của cả hai dự án hiện **không có stage lint hay test**. Bổ sung ngay ở bước 1 của lộ trình, trước khi đụng tới code.

## 7. Checklist thực thi

### 7.1 Trước khi bắt đầu

1. Tag commit baseline đang chạy ổn, để rollback.
2. Chạy `php -v` và `php -m` trong container production thật, ghi lại. Đừng tin tên image.
3. Dựng môi trường staging có đủ Mongo, Redis, Memcached, beanstalkd, Oracle (với hanmir) — vì lint không thay được chạy thật.
4. Bật đầy đủ `error_reporting(E_ALL)` và ghi log ở staging. Với hanmir, đồng thời **tắt** `display_errors` để Warning không lọt vào response JSON của API.
5. Thêm stage lint và `composer validate` vào pipeline.

### 7.2 Nhóm sửa theo thứ tự

| Thứ tự | Nhóm | Vì sao trước |
|---|---|---|
| 1 | `implode()` đảo tham số, hàm đã bị gỡ, constructor PHP 4, short tag | Fatal ngay khi đổi runtime |
| 2 | Tham số bắt buộc sau tham số có default | Deprecation nhưng sửa cơ học, làm sớm cho gọn |
| 3 | Package Composer | Nhiều lỗi sẽ tự biến mất khi package lên bản mới |
| 4 | Truyền NULL vào hàm internal, `count()` | Khối lượng lớn nhất, cần chia theo module |
| 5 | Dynamic property, `${var}`, `utf8_encode` | Deprecation, không chặn chạy |
| 6 | `is_resource()` trên object, extension chuyển PECL | Hỏng âm thầm, phải test chức năng |
| 7 | Class tích hợp interface nội bộ (`SessionHandlerInterface`) | Gắn liền với bước nâng framework |

### 7.3 Phải test bằng tay sau khi nâng

- Đăng nhập, đăng xuất, remember-me, regenerate session qua AJAX. Cả hai dự án dùng session driver Mongo tự viết, là phần dễ vỡ nhất.
- Gửi email qua IMAP và SMTP (`Imap.php` ở cả hai dự án).
- Xuất file Excel và CSV (PhpSpreadsheet đổi major version).
- Tải file lên và tải về qua route `upload/` (hanmir, vì `(:any)` đổi ngữ nghĩa).
- Worker và cron chạy dài: kiểm tra tên file log có roll over đúng ngày không.
- Các API trả JSON: xác nhận không có Warning của PHP lẫn vào body.
- Với hanmir: toàn bộ 25 module, vì routing module đi qua bootstrap tự chế.

### 7.4 Rollback

Giữ image cũ và tag cũ sẵn sàng. Với hanmir còn thêm một ràng buộc: khi `system/` bị gỡ khỏi repo để chuyển sang Composer, phải chắc `composer install` chạy được offline hoặc có mirror nội bộ, nếu không rollback sẽ kẹt.

## 8. Giới hạn của tài liệu

- Số liệu của hanmir là kết quả quét tĩnh, chưa chạy `php -l` hay test suite; các con số là cận dưới.
- Số liệu của jaccs dựa trên `php -l` đã chạy thật trên 8.3/8.4/8.5, nhưng chưa boot được ứng dụng nên phần runtime chưa kiểm chứng. Test suite của jaccs ghi nhận 63 pass và 6 fail, giống hệt nhau trên 8.4 và 8.5.
- Image `hub.southtelecom.vn/php7-oci-kafka` không pull được từ môi trường phân tích, nên phiên bản PHP và danh sách extension của hanmir mới chỉ suy ra từ tên image.
- hanmir không có `composer.lock`, nên version package đang chạy thật chưa xác định được.
