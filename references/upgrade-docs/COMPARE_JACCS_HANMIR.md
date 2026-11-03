> Bundled copy from the team's upgrade-ci docs, 2026-10-26. Source of truth: the original docs folder; re-copy to refresh.

# So sánh core, library và package: jaccs vs hanmir

Tài liệu so sánh hai codebase nội bộ cùng dòng sản phẩm WorldFone 4xs, nhằm lập kế hoạch nâng cấp cho hanmir.

- Nguồn: `<path>/jaccs`, `<path>/hanmir`
- Tree tham chiếu: `<path>/upgrade-ci/codeigniter-2.2.6` (<https://github.com/bcit-ci/CodeIgniter/tree/2.2.6>), `codeigniter-3.1.13` (<https://github.com/bcit-ci/CodeIgniter/tree/3.1.13>), `hoangkim28-codeigniter` (CI_VERSION `3.4.5`, <https://github.com/hoangkim28/codeigniter>)
- Ngày phân tích: 2026-10-26
- Phương pháp: đọc file, grep, diff tĩnh. Phần chạy thật được ghi rõ ở mục giới hạn.

## 1. Tóm tắt điều hành

**jaccs đã hoàn tất nâng cấp. hanmir thì chưa.**

jaccs không còn giữ `system/` trong repo; core được lấy qua Composer (`pocketarc/codeigniter` 3.4.4), runtime là PHP 8.5 trên Alpine, `php -l` sạch trên 8.3/8.4/8.5. hanmir vẫn là CI 3.1.9 bundled, core bị vá trực tiếp 5 chỗ, bootstrap bị copy nguyên vào `application/core/CodeIgniter.php`, `composer.json` còn khai báo `php >=5.6.4`, không có `composer.lock`, image chạy PHP 7 với mod_php.

Hai codebase dùng chung kiến trúc: prefix `WFF_`, `Mongo_db`/`Crud`, `Imap`, `Excel`/`Csv`, hook `Compress` và `Activity_log`, `Session_mongo_driver` trên MongoDB. Vì vậy **phần lớn bản vá của jaccs port thẳng sang hanmir được**, đặc biệt là `Session_mongo_driver` đã implement sẵn `CI_Session_driver_interface` — chính là điểm sẽ fatal ở hanmir.

Khác biệt lớn nhất quyết định khối lượng công việc: jaccs không có hacked core và không có bootstrap copy, hanmir có cả hai.

## 2. Bảng so sánh tổng quan

| Hạng mục | jaccs | hanmir |
|---|---|---|
| Trạng thái nâng cấp | Đã xong | Chưa bắt đầu |
| CI version | `pocketarc/codeigniter` 3.4.4 (constant đọc ra `3.4.2`) | `3.1.9` bundled (`system/core/CodeIgniter.php:58`) |
| Nguồn core | Composer, `index.php:123` → `vendor/pocketarc/codeigniter/system` | `system/` nằm trong repo |
| Hacked core | Không (chỉ thêm 2 file vào `system/`) | 5 entry bị sửa, xem mục 3.2 |
| Bootstrap | Dùng bootstrap của framework | Copy 581 dòng tại `application/core/CodeIgniter.php` |
| PHP khai báo | `composer.json` `"php": "^8.4"` | `composer.json` `php >=5.6.4` |
| PHP runtime | 8.5 (Alpine 3.24, `php85-*`) | 7.x (`hub.southtelecom.vn/php7-oci-kafka`) |
| Web server | nginx + php-fpm | Apache + mod_php |
| `composer.lock` | Có, lock platform `php ^8.4` | Không có, `vendor/` cũng gitignore |
| Lỗi PHP 8 còn lại | 13 điểm, phần lớn nằm ngoài `application/` | Trên 270 điểm, xem mục 6 |
| `php -l` | Sạch trên 8.3.33, 8.4.27, 8.5.12 | Chưa chạy được (không có PHP binary) |
| Prefix subclass | `WFF_` | `WFF_` |
| Class trong `application/core` | 2 | 6 cộng bootstrap copy |
| Store chính | MongoDB | MongoDB |
| SQL | Không dùng CI DB layer | `oci8` ở khoảng 8 file |
| Kiến trúc module | Không | HMVC thủ công, 25 module, 577 file PHP |
| Thư viện vendored ngoài Composer | Không có | phpseclib 1.0.x, Pheanstalk cũ, WClosure |
| CI/CD | base → build → Trivy → deploy, không có lint/test | build → push → ssh docker run, không pin PHP |

## 3. So sánh core framework

### 3.1 Cách nạp core

| | jaccs | hanmir |
|---|---|---|
| `$system_path` | `vendor/pocketarc/codeigniter/system` (`index.php:123`) | `system` (root `index.php`), `../system` (`public/index.php`) |
| Entry point | `index.php` nạp `vendor/autoload.php` rồi phpdotenv (`index.php:56-59`) | Root `index.php` cho cron, `public/index.php` cho web, DocumentRoot `/var/www/html/public` |
| `composer_autoload` | `FCPATH.'vendor/autoload.php'` (`config.php:141`) | `FALSE` (`config.php:141`); từng file tự `require FCPATH."vendor/autoload.php"`: `libraries/Csv.php:2`, `Excel.php:5`, `config/Dotenv.php:19` |
| `ENVIRONMENT` | `getenv('CI_ENV') ?: ($_SERVER['CI_ENV'] ?? 'production')` | `isset($_SERVER['CI_ENV']) ? ... : 'development'` (`index.php:56`), `.htaccess` đặt `SetEnv CI_ENV development` |
| `error_reporting` ở production | `E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT`, tức giấu toàn bộ deprecation | Mặc định `-1` khi `CI_ENV=development` (`index.php:57-62`), `.htaccess` bật `display_errors on` |

Hệ quả đáng lưu ý ở hanmir: `.htaccess` ép `CI_ENV=development` ngay cả trong image Docker, nên Warning của PHP 8 về undefined array key và undefined variable sẽ in thẳng vào response JSON của API. Trước khi nâng PHP, chuyển môi trường test sang `testing` hoặc `production`.

### 3.2 Core bị sửa trực tiếp

jaccs: `system/` của bản cũ (CI 3.1.9) **giống hệt upstream**, chỉ thêm hai file: `system/config/wffdata.json` và `system/.htaccess` (`Deny from all`). Không có gì phải re-apply. Khi cut-over sang Composer (commit `2d0a293`), đội đã thêm guard `file_exists()` tại `application/config/wff.php:47-53` và chuyển sang `System_config::load()` đọc cấu hình từ Mongo có cache Memcached (`wff.php:45-47`, commit `3076056`). File JSON thành dead code.

hanmir: 5 entry khác stock 3.1.9.

| Entry | Nội dung sửa | Xử lý khi nâng cấp |
|---|---|---|
| `system/core/Loader.php:138` | Thêm một dòng trống trong `__construct` | Bỏ, không cần re-apply |
| `system/database/DB_query_builder.php:970-980` | Đổi 4 literal LIKE thành `N'...'` (Unicode literal) | Fork vẫn giữ dạng thường tại `DB_query_builder.php:1051-1061`. Tác động nhỏ: `->like()` chỉ được gọi 3 lần, `oci8` chỉ dùng ở vài file |
| `system/libraries/Cache/Cache.php:62-63` | Thêm `rediscluster` và `mongodb` vào `$valid_drivers` | **Bắt buộc re-apply.** Fork không có (`Cache.php:57-65`). Làm ở tầng application: tạo `application/libraries/Cache/WFF_Cache.php` override `$valid_drivers`, thay vì vá core |
| `system/libraries/Cache/drivers/Cache_redis.php:206-208` | `delete($key)` đổi thành `unlink($key)`, comment "Fix loi redis php moi" | Bỏ. Fork đã dùng `static::$_delete_name` |
| `system/config/` (thêm mới) | `wffdata.json`, `wffdata.example.json` | **Di dời trước khi thay `system/`.** Chuyển sang `application/config/` và sửa hai nơi đọc: `application/config/wff.php:69`, `application/controllers/api/v1/Config.php:60` |

Thay `system/` nguyên khối ở hanmir sẽ xóa mất `wffdata.json`. File này còn chứa secret (`mobile_secret_key`, `crm_license_key`, `fcm_server_key`) và đang được track trong git.

Driver cache tùy biến của hanmir nằm ở `application/libraries/Cache/drivers/Cache_rediscluster.php` và `Cache_mongodb.php`.

### 3.3 Bootstrap

jaccs dùng bootstrap gốc của framework, không can thiệp.

hanmir ship một bản copy đầy đủ bootstrap 3.1.9 tại `application/core/CodeIgniter.php` (581 dòng). `index.php:312-319` và `public/index.php` chọn `APPPATH/core/CodeIgniter.php` thay cho `BASEPATH/core/CodeIgniter.php`. Bản copy khác stock ở ba điểm:

1. Gọi hook `pre_check_controller` (khoảng dòng 405) — hook point này **chỉ tồn tại nhờ bản copy**, không có trong framework.
2. Bọc phần resolve controller trong `if (empty($RTR->module)) { ... } else { ... }` tại dòng 412; nhánh `else` xử lý `_remap` cho controller của module (comment "Add 08/08/2022. Fix remap in module").
3. Vẫn dùng chữ ký 3.1.9: `load_class('Hooks'|'Utf8'|'URI'|'Security'|'Input','core')` không truyền tham số.

Điểm 3 **sẽ fatal trên fork**, vì constructor của `CI_Hooks`, `CI_Utf8`, `CI_URI`, `CI_Security`, `CI_Input` nay nhận tham số (`CI_Config`, `$charset`, `CI_Security`).

Cách xử lý: rebase từ `system/core/CodeIgniter.php` của fork, chỉ re-apply lời gọi `pre_check_controller` và nhánh `$RTR->module`. Đồng thời xóa block chết `!is_php('5.4')` có tham chiếu `$HTTP_RAW_POST_DATA` tại `application/core/CodeIgniter.php:105`.

### 3.4 Khác biệt giữa `pocketarc` 3.4.4 và `hoangkim28` 3.4.5

jaccs đang ở `pocketarc/codeigniter` 3.4.4. Fork `hoangkim28/codeigniter` 3.4.5 (Packagist `v0.2.1`, 2026-10-23) khác 14 file. Với jaccs, chỉ hai nhóm có ý nghĩa:

| File | Thay đổi | Ảnh hưởng jaccs |
|---|---|---|
| `libraries/Session/Session.php`, `PHP8SessionWrapper.php` | Bọc `session_start` và `session_regenerate_id` trong try/catch với `_unmask_handler_error`; `PHP8SessionWrapper` thêm `create_sid()` gọi `session_create_id()` và sửa một typo trong `updateTimestamp` | Có. Phải retest `Session_mongo_driver` |
| `core/Log.php` | Tên file log mặc định được tính lại theo ngày ở mỗi lần ghi | Có lợi: container worker/cron chạy dài sẽ tự roll over lúc nửa đêm |
| `core/Loader.php`, `database/drivers/pdo/*`, `libraries/Encryption.php`, `Cache/drivers/Cache_redis.php`, `Cart.php`, `Xmlrpc.php`, `Xmlrpcs.php`, `helpers/string_helper.php`, `helpers/text_helper.php`, `core/CodeIgniter.php` | Gỡ DebugBar, dùng `Pdo\Mysql::ATTR_*`, decrypt giữ NULL, guard `expireAt`, các fix nhỏ, bump version | Không. Các thành phần này jaccs không dùng |

Nếu đổi sang fork, phải sửa đường dẫn `vendor/pocketarc/codeigniter/system` tại `index.php:123`, `tests/Bootstrap.php:7`, khoảng 20 file trong `tests/**` và `tests/security/composer_contract_test.php:9`.

## 4. So sánh core extension của ứng dụng

Cả hai đều dùng `subclass_prefix = 'WFF_'` và bật `enable_hooks`. Không codebase nào có class `MY_*`.

| Thành phần | jaccs | hanmir | Tương thích fork |
|---|---|---|---|
| `WFF_Controller` | Có, 252 dòng. `__construct()` gọi parent rồi nạp session, authentication, chạy `check_login`, `enforce_password_expiration`, `check_page_module`. Định nghĩa `_remap($method,$params=[])`, `_build_template()` | Có. `__construct()` gọi parent rồi `load->library('session')`. Override `_remap`, thêm `_build_template` | Cả hai OK. `CI_Controller` của fork có `#[AllowDynamicProperties]` |
| `WFF_Output` | Có, 140 dòng. Override `_display($output='')` gọi `parent::_display($output)` (`WFF_Output.php:71`) | Có. Override `_display($output='')`, thêm `set_template`, `unset_template`, `set_mode`, `get_template_output`, `translate` | Cả hai OK. Fork đổi chữ ký thành `_display($output = NULL)`; override không khai báo type nên `if ($output == '')` vẫn bắt được NULL |
| `WFF_Input` | Không có | Có. `__construct()` gọi `parent::__construct()` **không tham số** (`:46`); override `get`, `post`, `input_stream`; thêm `json`; public prop `$get`, `$post`, `$input` | **Vỡ.** Fork yêu cầu `CI_Input::__construct(CI_Security &$security)` (`Input.php:107`) nên sẽ `ArgumentCountError` |
| `WFF_Log` | Không có | Có. Copy nguyên `write_log()` (`:17-85`); thêm `notify_error`, `write_log_db`, `get_backtrace` | **Vỡ ngầm.** Dùng `$this->_file_ext` (`:38`, `:45`) trong khi fork đã đổi sang `_log_filename` / `_log_filename_dated` (`Log.php` khoảng `:64-72`) |
| `WFF_Security` | Không có | Có. Copy nguyên `xss_clean()` bản 3.1.9 (`:15-242`); chỉ khác stock ở một guard non-string (`:17-21`) | Compile được nhưng là bản copy đã cũ |
| `WFF_Loader` | Không có | Có. Override `add_package_path` (thêm `_ci_files_paths`); thêm `abs_view`, `third_party`; `protected function &_ci_get_component` null-safe | OK. Fork vẫn giữ `add_package_path` (`Loader.php:786`), `_ci_view_paths`, `_ci_*_paths`, `&_ci_get_component` (`:1430`) |
| `WFF_Session` | Không có | Có (`libraries/Session/WFF_Session.php`). `__construct(array $params=[])`, return sớm khi `is_cli()` hoặc thiếu `HTTP_USER_AGENT` | OK. Khớp `CI_Session::__construct(array $params=[])` (`Session.php:71`); fork đã tự abort dưới CLI nên chỉ còn phần kiểm tra user-agent là riêng |
| `Session_mongo_driver` | `CI_Session_mongo_driver extends CI_Session_driver implements SessionHandlerInterface, CI_Session_driver_interface`. Có đủ `open`, `read`, `write`, `close`, `destroy`, `gc`, `updateTimestamp`, `validateId`, tất cả kèm `#[\ReturnTypeWillChange]` (`:86-310`) | `CI_Session_mongo_driver extends CI_Session_driver implements SessionHandlerInterface` (`:13`). Chỉ có `open`, `read`, `write`, `close`, `destroy`, `gc` (`:118-271`) | jaccs OK. **hanmir vỡ**: `CI_SessionWrapper::__construct(CI_Session_driver_interface $driver)` của fork type-hint interface mới |
| Bootstrap copy | Không | Có, 581 dòng | Xem mục 3.3 |

Bốn việc phải làm ở hanmir, bám theo bản đã chạy của jaccs:

1. `WFF_Input`: đổi thành `__construct(CI_Security &$security) { parent::__construct($security); ... }`. `_fetch_from_array(&$array, ...)` và `__get('raw_input_stream')` vẫn còn trong fork nên phần override giữ nguyên được. Lưu ý fork đã bỏ `_sanitize_globals()`, nên `$_GET`, `$_POST`, `$_COOKIE` không còn được làm sạch.
2. `WFF_Log`: viết lại `write_log()` thành chạy các helper phụ rồi `return parent::write_log($level, $msg)`. Giữ nguyên bản copy sẽ cho ra tên file `log-YYYY-MM-DD.` thiếu phần mở rộng và mất header chặn truy cập PHP. Biến `$result` cũng chưa khởi tạo khi message rỗng. `utf8_encode` tại `:114` deprecated từ 8.2.
3. `WFF_Security`: thay bằng wrapper mỏng, áp guard non-string rồi gọi `parent::xss_clean()`.
4. `Session_mongo_driver`: port từ jaccs. Thêm `implements CI_Session_driver_interface`, bổ sung `updateTimestamp($id, $data)` và `validateId($id)`, trả về đúng kiểu `bool` vì wrapper PHP 8 khai báo `: bool`. Sửa `${self::class}` (`:44`) và prop chưa khai báo `$_row_exists` (`:176-192`).

### 4.1 Hook

| Hook point | jaccs | hanmir |
|---|---|---|
| `display_override` | `Compress.php` → `compress()`, gọi `$CI->output->_display()` | `Compress.php` → `compress()`, giống jaccs |
| `post_system` | `Activity_log.php` | `WFF_Activity_log` |
| `post_controller_constructor` | `Auth_gate.php`, đọc `$CI->router->directory` và class | `WFF_Middleware::boot`, chạy các class trong `$CI->middlewares` từ `MODULEPATH` hoặc `APPPATH` `middlewares/` |
| `pre_check_controller` (hook point tự chế) | Không có | `WFF_Module::pre_check_controller` |
| Không wire trong `hooks.php` | — | `WFF_Third_party` (được `WFF_Loader::third_party()` include trực tiếp) |

`WFF_Module` là điểm rủi ro riêng của hanmir: dùng `global $RTR, $class, $method, $URI`, ghi dynamic property `$this->module_path` chưa khai báo (`:42`) và `$this->_RTR->module` (`:113`) lên `CI_Router` — class này **không** có `#[AllowDynamicProperties]`, nên PHP 8.2 sẽ cảnh báo deprecated. Phần `_parse_routes` và `_set_request` bên trong là bản copy logic `CI_Router` 3.1.9.

### 4.2 Nguy cơ về casing khi load

jaccs: toàn bộ 406 controller, 35 model, 32 library đều viết hoa chữ đầu, không file nào vỡ loader. Các điểm cần dọn: `controllers/api/report/loan/New_block_card_report.php:12` khai báo class `Block_card_report_new` (trùng với `Block_card_report_new.php:12`, không route tới được, nên xóa); các file mixed case như `SmsDailyUp.php`, `ExcecuteExcel.php`, `TS_rate.php` chỉ chạy khi URL đúng y nguyên case.

hanmir: không có file viết thường chữ đầu trong `application/`, nhưng còn:

| File | Vấn đề |
|---|---|
| `modules/sla/controllers/api/v1/sla.php` | Khai báo class `Sla`; loader `ucfirst` rồi `file_exists('.../Sla.php')` nên hỏng trên Linux |
| `application/models/NumberID_model.php` | Khai báo `class NumberId_model`; tên gọi khi load phải khớp đúng case của filename |
| `Organization_Origrin.php` (class `Organization`), `Crud_Origrin.php` (class `Crud`), `Excel.php` (khai báo cả `MyReadFilter` lẫn `Excel`) | File backup hoặc trùng, không load được theo filename |
| `models/Collections/*`, `models/Handlers/*`, `modules/tool/models/Collections/*`, `api/wf4x/ConvertTemplateHelper.php`, `api/wf4x/QueryDwhHelper.php` | Không khai báo class nào, không phải subclass của `CI_Model` |

### 4.3 Thay đổi hành vi của fork tác động tới hanmir

| Thay đổi | Chi tiết | Tác động |
|---|---|---|
| Phạm vi biến của view | Fork thay cơ chế dồn `_ci_cached_vars` bằng stack biến theo từng lần gọi; biến truyền vào một `load->view()` không còn rò sang view nạp sau, trừ khi đi qua `load->vars()` | hanmir có 99 lời gọi `load->view()` một tham số và **không** dùng `load->vars()` lần nào. Phải test các view dựa vào biến rò |
| Bỏ `rewrite_short_tags` | 3 view còn dùng short tag `<?` | Phải đổi sang `<?php` |
| `(:any)` đổi từ `.+` thành `[^/]+` | Route `upload/(:any)...` trong `config/routes.php` xếp từ 5 segment xuống 1 | URL từ 6 segment trở lên, hoặc có sub-path ở segment cuối, sẽ 404 |
| `Loader::database()` mất tham số thứ ba | — | Không ảnh hưởng, app chưa bao giờ truyền |
| Route theo HTTP verb | `['GET']`, `['PATCH']` vẫn chạy | Không ảnh hưởng |

## 5. So sánh library

### 5.1 Library của ứng dụng

| Nhóm | jaccs | hanmir |
|---|---|---|
| Wrapper Mongo | `Mongo_db` (2150 dòng), `Mongo_db4x` (672), `Mongo_private` (250) | `Mongo_db`, `Mongo_private`, `Mongo_secondary` (mỗi file khoảng 2200 dòng) |
| CRUD trên Mongo | `Crud`, `Cruds`, `Kendo_aggregate`, `Mongodatasourceresult` | `Crud`, `Cruds`, `Crud_secondary`, `Cruds_secondary`, `Crud_Origrin`, `Model_data`, `Kendo_aggregate` |
| Spreadsheet | `Excel`, `Csv`, `Calling_list_file_reader`, `Sms_daily_export`, `Write_off_year_range` | `Excel`, `Csv` |
| Mail | `Imap` (1449 dòng) | `Imap` (43 lời gọi `imap_*`) |
| Queue | `Pheanstalk` wrapper (42 dòng) | `Queue/*` (beanstalkd, redis, sync) trên `CI_Driver_Library` |
| Cache tùy biến | Không | `Cache/drivers/Cache_rediscluster.php`, `Cache_mongodb.php` |
| Broadcast | Không | `Broadcast/*` (redis, log, dummy) |
| JWT | Không | `Jsonwebtoken.php` + `helpers/jwt_helper.php` |
| Ảnh | `Text_to_image` (ext-gd) | `Text_to_image` (ext-gd, 18 lời gọi `image*`) |
| Migration | Không dùng | `WFF_Migration.php` |
| Nghiệp vụ | `Authentication`, `System_config`, `Core_api_config`, `Core_contract_client`, `Cache_lock`, `Cache_version`, `Ping_rate_limiter`, `Contract_call_limit`, `Agent_state_snapshot`, `Calling_list_audit`, `Calling_list_validator`, `Import_window`, `Investigation_rule`, `Payment_status_rule`, `Pbx_call_event_log` | — |
| Library chết | `Googleplus` (thiếu `APPPATH/third_party/google-login-api`), `third_party/cli/samplecontroller.php` | `load->library('googleplus')` tại `Action.php:91` và `load->library('pheanstalk')` tại `modules/sla/.../Export.php:22` trỏ tới library không tồn tại trong repo |

### 5.2 Helper

| | jaccs | hanmir |
|---|---|---|
| Số file | 5 | 8 |
| Danh sách | `common_helper` (257 dòng), `curl_helper`, `xml_helper`, `server_helper`, `gmail_helper` | `common_helper` (630 dòng), `crypt_helper`, `curl_helper`, `gmail_helper`, `jwt_helper`, `mycaptcha_helper`, `server_helper`, `xml_helper` |
| Autoload | helper `url`, `common`; config `_mongo`, `wff` | helper `url`, `common`, `crypt` |
| Hàm env | `config/Dotenv.php` định nghĩa `env()`, `env_bool()`, `env_required()` | `config/Dotenv.php` tự `require vendor/autoload.php` |

`common_helper.php:470` của hanmir định nghĩa một global `class Promise` dùng closure serialize qua `WClosure`.

### 5.3 Thư viện vendored ngoài Composer

jaccs: `application/third_party/` chỉ có `cli/` (worker, scanjob, test driver Mongo, sample controller) và `index.html`. **Không có thư viện PHP nào được copy tay.**

hanmir:

| Thư viện | Vị trí | Vấn đề |
|---|---|---|
| phpseclib 1.0.x | `application/third_party/phpseclib`, trùng lặp ở `cronjob/phpseclib` | Bản copy 22k dòng, API cũ (`Crypt_AES`, method prefix gạch dưới). Nạp bởi `crypt_helper.php:19-20`, `Api_model.php:55-56`, `database_guest/.../User.php:12-13`, `Config_db_guest.php:12-13`. `create_function` (`Base.php:2558`, `X509.php:3004`) và 35 lời gọi `mcrypt_*` đều có guard `version_compare` hoặc `function_exists` nên không chạm trên PHP 8 |
| `WClosure.php` | `application/third_party/` | Extends `\Opis\Closure\SerializableClosure`, override `serialize()`, phụ thuộc internal của opis (`$scope`, `$reference`, `getReflector`, `securityProvider`); set dynamic prop `reference` và `scope`; phụ thuộc interface `Serializable` đã deprecated từ 8.1 |
| Pheanstalk cũ | `public/other/beanstalk_monitor/lib/Pheanstalk*` | `ClassLoader` tham chiếu `__autoload()` (có guard `function_exists`) |
| proui, kendo, ckeditor | `public/` (20 MB + 51 MB) | Một sample còn gọi `get_magic_quotes_gpc()` |
| `composer.phar` | Root repo | 1.97 MB, commit vào git, không rõ version |

### 5.4 Library của CI thực sự được dùng

| Library | jaccs | hanmir |
|---|---|---|
| `session` | 49 | 650 |
| `cache` driver | 39 (36 dùng `memcached` backup `file`) | 155 (có `rediscluster`, `mongodb`) |
| `security` | — | 47 |
| `email` | 1 (`Email_model.php:71`) | 15 (toàn bộ ở `Email_model.php:103`) |
| `parser` | 2 | 8 |
| `user_agent` | 1 | 5 |
| `lang` | — | 7 |
| `migration` | Không dùng | 3 |
| `benchmark` | — | 2 |
| Không dùng ở cả hai | `form_validation`, `upload`, `image_lib`, `encrypt`/`encryption`, `cart`, `xmlrpc`, `pagination`, `javascript`, `ftp`, `zip`, `calendar`, `table` | |

Tải trọng chính của jaccs: 316 lời gọi `load->library("crud")` và 137 + 55 lời gọi `mongo_db`. Tổng của hanmir trên `application/` và `modules/`: `load->library` 880, `load->model` 356, `load->view` 157, `load->config` 147, `load->driver` 101, `load->helper` 17, `load->third_party` 11, `load->database` 10, `add_package_path` 5.

Cả hai đều **không dùng CI DB layer cho dữ liệu chính**. jaccs khai báo `mysqli` từ env trong `config/database.php` nhưng không có lời gọi `load->database` nào, `$this->db` chính là wrapper Mongo. hanmir dùng `oci8` cho 2 group (`default`, `report`), chỉ xuất hiện ở khoảng 8 file: `api/wf4x/Test.php`, `QueryDwhHelper.php`, `Db_guest_model.php`, `modules/database_guest/*`.

## 6. So sánh package

### 6.1 Bảng đối chiếu Composer

| Package | jaccs | hanmir | Ghi chú |
|---|---|---|---|
| Ràng buộc PHP | `^8.4` | `>=5.6.4` | hanmir cần cập nhật |
| `composer.lock` | Có | **Không** | Không có lock nghĩa là không biết version đang chạy thật |
| Framework CI | `pocketarc/codeigniter` `^3.4` → 3.4.4 | Không qua Composer | |
| `phpoffice/phpspreadsheet` | `^2.0` → 2.4.7 | `^1.7` | Bản 1.7 quá cũ cho 8.1+; cần 1.2x trở lên hoặc 2.x. Lưu ý 2.4.7 yêu cầu `<8.6.0`, tức trần hiện tại là PHP 8.5 |
| `pda/pheanstalk` | `^3.2` → v3.2.1 | `^3.2` | Dòng 2017, chưa bị gắn cờ abandoned. v4 cần PHP 7.1+, v5 cần 8.1+ và đổi API. hanmir dùng API cũ `new Pheanstalk($host,$port)` (`Queue_beanstalkd.php:71`) |
| `vlucas/phpdotenv` | `^5.6` → 5.6.4 | `^4.1` | hanmir nên lên v5 |
| `mongodb/mongodb` | Không khai báo (dùng raw driver) | `^1.4` | Quá cũ. ext-mongodb cho 8.1-8.4 cần library 1.15+, ext 1.21 cho 8.4 |
| `firebase/php-jwt` | Không dùng | `^5.2` | Chạy được trên 8.x kèm deprecation. Lên v6 phải đổi `decode($jwt, new Key($key,$alg))`, ảnh hưởng `Jsonwebtoken.php:42,54` |
| `phpoffice/phpword` | Không dùng | `^0.17.0` | Cần 0.18 hoặc 1.x cho 8.x |
| `dompdf/dompdf` | Không dùng | `^0.8.3` | Quá cũ, cần 1.x hoặc 2.x |
| `gears/pdf` | Không dùng | `*` | Không pin, không xác định được. Coi như abandoned cho tới khi xác minh |
| `dragonmantank/cron-expression` | Không dùng | `^1.2` | Cũ, hiện tại là 2.x/3.x |
| `predis/predis` | Không dùng | `^1.1` | Dùng 1.1.10+ hoặc 2.x (`Queue_redis.php:85`) |
| `league/oauth2-client` | Không dùng | `^2.4` | Nâng lên 2.6+ |
| `microsoft/microsoft-graph` | Không dùng | `^1.12` | Cũ, gắn với Guzzle 6/7, cần kiểm tra ràng buộc Guzzle |
| `simplario/quedis` | Không dùng | `^2.0` | **Abandoned** |
| `opis/closure` | Không dùng | `^3.6` | **Abandoned**, thay bằng `laravel/serializable-closure`; `WClosure` bám vào internal của nó |
| `phpunit/phpunit` (dev) | `^9.0` → 9.6.35 | `4.*` hoặc `5.*` | Bản 4/5 không chạy được trên PHP 8 |
| Transitive của jaccs | `maennchen/zipstream-php`, `markbaker/*`, `psr/simple-cache`, `symfony/polyfill-*`, `composer/pcre`, `graham-campbell/*`, `phpoption/phpoption`, `mikey179/vfsstream` 1.6.12 | — | Đều hợp lệ trên 8.x |

jaccs **không còn package abandoned hay không tương thích PHP 8**. Không có PHPExcel, mcrypt, PHPMailer cũ, TCPDF, FPDF. hanmir có 2 package abandoned và 8 package quá cũ.

### 6.2 Manifest phụ

| | jaccs | hanmir |
|---|---|---|
| Scheduler riêng | `cronjob/console/composer.json`: PHP `^8.4`, `laravel/lumen-framework ^11.2` (đã hết hạn security support), `vlucas/phpdotenv ^5.6`, dev PHPUnit 10.5 + Mockery | Không có |
| Tool kèm theo | `public/other/beanstalk_monitor/composer.json` (`ptrofimov/beanstalk_console`, PHP `>=5.2`), `public/other/flappybird`, `mongo_monitor/top.php` | `public/other/beanstalk_monitor` (72 file), `mongo_monitor` |
| Python | `cronjob/python/requirements.txt`: `pymongo >=4,<5`, `pandas >=2,<3`, `xlsxwriter`, `openpyxl`, `python-dateutil` | Không khảo sát |

## 7. So sánh hạ tầng và runtime

| Hạng mục | jaccs | hanmir |
|---|---|---|
| Base image | `alpine:3.24`, `php85-*`, binary `/usr/bin/php85`, ini `/etc/php85/conf.d/99-jaccs.ini` | `hub.southtelecom.vn/php7-oci-kafka:latest` (một dòng comment trỏ `php7-4xs-v5`) |
| Web stack | nginx + php-fpm. Chỉ `index.php` và `ping.php` được chạy PHP, `.php` khác trả 404. Có route SSE `/api/v1/ping/sse` | Apache + mod_php, DocumentRoot `/var/www/html/public`, `AllowOverride All` |
| Extension cài trong image | `php85-pecl-mongodb ~2.3.3`, `php85-pecl-memcached`, cùng `ctype curl dom fileinfo gd iconv intl mbstring mysqli openssl pdo_mysql pdo_sqlite posix session simplexml sodium sqlite3 tokenizer xml xmlreader xmlwriter zip zlib OPcache` | oci8, rdkafka theo tên image; `sed` nâng `upload_max_filesize` và `post_max_size` lên 20M |
| Thiếu extension | **`ftp` và `imap`** đều không được cài dù code có dùng | Chưa kiểm chứng (không pull được image) |
| Scheduler | supercronic v0.2.48 (không verify checksum), `docker/cron/crontab` + `scheduler.crontab`, lịch động trong collection Mongo `Schedule_task` | cron cài từ `cron/scheduler`, vá `cron` và `service cron start` vào `apache2-foreground`; chạy `php index.php cli queue work`, `cli schedule run`, `cli queue single runCommand` mỗi phút |
| Orchestration | `docker-compose.yml` dạng Swarm stack: `app` x2, `worker`, `cron` x1, `beanstalkd`; Memcached và Mongo bên ngoài | `.gitlab-ci.yml` dùng `docker:19.03.1` dind, tag `uat-old`, chỉ chạy trên nhánh `uat`, build rồi ssh tới host chạy `docker run` với `-p 8080:80 -p 8443:443` và mount nas |
| Pipeline | base → build → Trivy scan (`allow_failure`) → deploy. **Không có stage lint, test hay `composer validate`** | build → push → deploy. Không pin PHP version |
| `.htaccess` | Còn dòng `php_flag`/`php_value` nhưng đã vô hiệu vì chạy nginx | `php_flag`/`php_value` đang có hiệu lực: `display_errors on`, `memory_limit -1`, `max_execution_time 0`, `post_max_size 0`, `error_log /var/www/html/worldfone4xs/PHP_errors.log` (thư mục không tồn tại). **Các dòng này gây HTTP 500 khi chuyển sang php-fpm** |
| Secret trong repo | `.env.dev` được track | `.env` được track; `application/config/database.php:79-80` và `:101-102` hard-code credential Oracle; `system/config/wffdata.json` chứa `mobile_secret_key`, `crm_license_key`, `fcm_server_key`; `helpers/crypt_helper.php:23` và `models/Api_model.php:58` hard-code khóa AES; chứng chỉ `.crt`/`.key` nằm trong `apache2/ssl/` |
| Endpoint lạc | `public/other/*` | `public/phpinfo.php` (lời gọi đã comment), `tests/phpinfo.php` còn `phpinfo()` sống nhưng nằm ngoài web root |

Hai điểm khác biệt về hạ tầng quyết định kế hoạch cho hanmir: chuyển mod_php sang php-fpm bắt buộc phải gỡ `php_flag`/`php_value` khỏi `.htaccess` và đưa vào `php.ini` hoặc pool config; và `oci8` cùng `rdkafka` là PECL, nên base image mới phải build lại chứ không dùng được image Alpine của jaccs nguyên trạng.

## 8. Điểm chung và cơ hội tái sử dụng

Hai codebase cùng một dòng sản phẩm, nên các thành phần sau gần như song sinh:

| Thành phần | Mức tương đồng | Bản vá của jaccs có port được không |
|---|---|---|
| `Session_mongo_driver` | Cùng vai trò, hanmir thiếu 2 method và interface mới | **Có.** Đây là bản port giá trị nhất |
| `WFF_Controller`, `WFF_Output` | Cùng thiết kế `_remap` + `_build_template` + `_display` | Có, nhưng hanmir đã tương thích nên không gấp |
| Hook `Compress` (`display_override`), `Activity_log` (`post_system`) | Gần như giống hệt | Có |
| `Mongo_db` / `Mongo_private` | Cùng gốc, hanmir có thêm bản `_secondary` | **Có.** jaccs đã sửa `implode()` đảo tham số và `${var}` trong bản `application/libraries`; hanmir còn nguyên 7 chữ ký required-after-optional mỗi file |
| `Crud` / `Cruds` / `Kendo_aggregate` | Cùng gốc | Có |
| `Imap.php` | Cùng gốc | Một phần. Cả hai đều còn vấn đề `is_resource()` và extension `imap` |
| `Excel` / `Csv` trên PhpSpreadsheet | Cùng vai trò | Có, kèm việc nâng PhpSpreadsheet lên 2.x |
| `common_helper`, `curl_helper`, `xml_helper`, `server_helper`, `gmail_helper` | Cùng tên, hanmir có thêm 3 helper | Một phần |
| `config/Dotenv.php` | Cùng cơ chế `env()` | Có |
| Cấu hình `subclass_prefix = WFF_`, `enable_hooks`, `sess_driver = mongo`, `csrf_protection = FALSE`, `global_xss_filtering = FALSE` | Giống nhau | — |

Kết luận thực hành: dựng nhánh nâng cấp hanmir bằng cách **diff từng library cùng tên với bản jaccs** rồi lấy về các fix đã được kiểm chứng, thay vì sửa lại từ đầu. Báo cáo `docs/kaizen/...php84-upgrade-report.md` trong repo jaccs là nhật ký nâng cấp có sẵn, nên đọc trước khi lập kế hoạch.

## 9. Khoảng cách cần lấp cho hanmir

Xếp theo thứ tự thực hiện. Chi tiết thao tác PHP nằm ở `UPGRADE_PHP.md`; chi tiết thao tác CodeIgniter nằm ở `UPGRADE_FROM_3.1.13.md`.

| # | Việc | Mức chặn | Tham chiếu jaccs |
|---|---|---|---|
| 1 | Di dời `system/config/wffdata.json` và `wffdata.example.json` ra khỏi `system/`, sửa `application/config/wff.php:69` và `api/v1/Config.php:60` | Chặn | jaccs làm đúng việc này ở commit `2d0a293`, kèm guard `file_exists()` tại `wff.php:47-53`, sau đó chuyển hẳn sang `System_config::load()` đọc từ Mongo |
| 2 | Chuyển core sang Composer, bỏ `system/` khỏi repo | Chặn | `index.php:123` của jaccs |
| 3 | Rebase `application/core/CodeIgniter.php` lên bootstrap của fork, chỉ giữ `pre_check_controller` và nhánh `$RTR->module` | Chặn | jaccs không có bootstrap copy, không có mẫu sẵn |
| 4 | Sửa constructor `WFF_Input`, viết lại `WFF_Log::write_log()`, thu gọn `WFF_Security::xss_clean()` | Chặn | jaccs không có 3 class này, nên bỏ hẳn cũng là một lựa chọn |
| 5 | Port `Session_mongo_driver` từ jaccs (thêm `CI_Session_driver_interface`, `updateTimestamp`, `validateId`, kiểu trả về `bool`) | Chặn | `application/libraries/Session/drivers/Session_mongo_driver.php:86-310` |
| 6 | Tạo `application/libraries/Cache/WFF_Cache.php` override `$valid_drivers` để giữ `rediscluster` và `mongodb` | Chặn | Không có ở jaccs (jaccs dùng memcached) |
| 7 | Viết `composer.json` mới (`"php": "^8.4"`), nâng toàn bộ package, sinh và commit `composer.lock` | Chặn | `composer.json` + `composer.lock` của jaccs |
| 8 | Thay phpseclib 1.0.x bằng `phpseclib/phpseclib` v3 (đổi API AES), thay `opis/closure` và `simplario/quedis` | Cao | jaccs đã bỏ hết thư viện vendored |
| 9 | Sửa các lỗi PHP 8: 6 `implode()` đảo tham số, 17 chữ ký required-after-optional, 7 chuỗi `${}`, 2 `utf8_encode()`, 28 short tag, 3 `is_resource()` trên `IMAP\Connection` | Cao | jaccs đã sửa các bản copy trong `application/libraries` |
| 10 | Rà soát trên 210 vị trí truyền NULL vào hàm nội bộ và 358 lời gọi `count()`/`sizeof()` | Cao | jaccs còn 7 vị trí tương tự chưa guard |
| 11 | Kiểm tra lại route `upload/(:any)` vì `(:any)` đổi thành `[^/]+` | Trung bình | Không có ở jaccs |
| 12 | Test 99 lời gọi `load->view()` một tham số vì phạm vi biến đổi | Trung bình | Không có ở jaccs |
| 13 | Chuyển Apache + mod_php sang nginx + php-fpm, gỡ `php_flag`/`php_value` khỏi `.htaccess`, bỏ `SetEnv CI_ENV development` | Trung bình | `docker/nginx-default.conf`, `docker/php-fpm*.conf` của jaccs |
| 14 | Dựng base image PHP 8.x có `oci8`, `rdkafka`, `mongodb`, `redis`, `imap`, `gd`, `soap`, `curl` | Trung bình | `docker/Dockerfile.base` của jaccs, nhưng phải thêm PECL `oci8` và `rdkafka` |
| 15 | Thêm stage lint, test và `composer validate` vào pipeline | Trung bình | jaccs cũng đang thiếu, nên làm đồng thời cho cả hai |
| 16 | Xoay vòng toàn bộ secret đang nằm trong git | Cao, độc lập với nâng cấp | jaccs cũng còn `.env.dev` trong git |

## 10. Giới hạn của phân tích

- Không có PHP binary trên máy phân tích hanmir, nên mọi kết luận PHP 8 của hanmir đến từ grep và quét tĩnh. Các con số là cận dưới.
- Với jaccs, `php -l` đã chạy thật trên PHP 8.3.33, 8.4.27, 8.5.12 qua Docker và cho kết quả sạch; nhưng không boot được ứng dụng (thiếu Mongo, Memcached, Beanstalk), nên các lỗi runtime như truyền NULL vào hàm nội bộ, `count()` trên giá trị không đếm được, so sánh chuỗi với số, hay gọi static vào method non-static vẫn chưa được kiểm chứng.
- hanmir không có `composer.lock` nên version package thực tế đang chạy không xác định được; bảng mục 6 dựa trên ràng buộc trong `composer.json`.
- Image `hub.southtelecom.vn/php7-oci-kafka` không pull được từ môi trường phân tích, nên version PHP và danh sách extension của hanmir chỉ suy ra từ tên image.
- Các nhóm lỗi không thể bắt bằng grep: truyền NULL vào tham số không nullable, ép kiểu float sang int ngầm, thay đổi so sánh chuỗi với số, gọi static vào method non-static.
