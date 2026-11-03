> Bundled copy from the team's upgrade-ci docs, 2026-10-26. Source of truth: the original docs folder; re-copy to refresh.

# Nâng cấp CodeIgniter 2.2.6 → Fork "3.4.5" (hoangkim28)

Tài liệu dành cho application đang chạy CodeIgniter 2.2.6 và muốn nâng lên fork
`hoangkim28/codeigniter` (nhãn `CI_VERSION = '3.4.5'`, repo
<https://github.com/hoangkim28/codeigniter>).

> **Lưu ý:** "3.4.5" là community fork xây trên nhánh 3.2.0-dev chưa phát hành, không phải
> bản chính thức của BCIT. Xem [README.md](README.md) mục 2. Đây là nhảy hai bản chính
> thức (2.x → 3.x → fork); cân nhắc nâng hai giai đoạn qua 3.1.13 nếu app lớn
> (xem README mục 4).

## 1. Yêu cầu môi trường (blocking)

- PHP ≥ 5.4.8 với fork. App 2.2.6 thường giả định PHP 5.2/5.3 — cần nâng PHP trước.
- **Chuyển driver DB `mysql` → `mysqli`** trong `database.php`: `mysql_connect()` đã bị
  gỡ trên PHP ≥ 7. Driver `mysql` legacy còn trong fork nhưng fatal khi gọi.
  Tương tự: `mssql`, `sqlite` (v2), `pdo/dblib` không dùng được — dùng `sqlsrv`, `sqlite3`, `pdo/*`.
- Thay `index.php` và áp lại các setting `$system_path`, `$application_folder`, `$view_folder`.
  Hằng **`EXT` bị gỡ** — tìm và xóa mọi chỗ dùng `EXT`.
- `BASEPATH`, `APPPATH`, `FCPATH` giờ dùng `DIRECTORY_SEPARATOR` (nên `\` trên Windows)
  thay vì chuẩn hóa về `/` — code so sánh/chuỗi these paths có thể vỡ trên Windows.
- Set `base_url` tường minh (auto-detect dùng `SERVER_ADDR`, không tin cậy).
- `ENVIRONMENT` lấy từ `$_SERVER['CI_ENV']`, mặc định `'development'`.

## 2. Đổi tên file bắt buộc (Ucfirst) — làm trước, cơ học

Loader giờ `ucfirst()` tên khi tìm file: `models/<Name>.php`, `libraries/<Name>.php`
(2.2.6 viết thường). **Đổi tên mọi controller, model, library, driver, file `MY_*` về Ucfirst:**

- `welcome.php` → `Welcome.php`
- `misc_model.php` → `Misc_model.php`
- `my_email.php` → `MY_Email.php`
- Thư mục, config, view, helper, hooks, language **giữ nguyên chữ thường**.

Trên Linux sai chữ hoa/thường khiến file không load được → 404 im lặng.

Các bước cơ học khác:

- Di chuyển `application/errors/*` → `application/views/errors/html/` (thêm
  `error_exception.php`) và copy bộ `errors/cli/` mới.
- Di chuyển override `application/libraries/[MY_]Log.php` → `application/core/` (Log
  chuyển từ `system/libraries/Log.php` sang `system/core/Log.php`; `write_log()` bỏ
  tham số `$php_error`).
- Gỡ `$autoload['core']` (chuyển mục sang `libraries`); thêm key `drivers` vào `autoload.php`.
- `database.php`: xóa `$active_record` (Query Builder giờ qua `$query_builder`, nhưng fork
  luôn bật QB), xóa `autoinit`, set `dbdriver=mysqli`.

## 3. Session — viết lại hoàn toàn

API 2.x và fork **không tương thích**. Sessions chạy server-side qua
`session_set_save_handler` với driver `files`/`database`/`redis`/`memcached`; dữ liệu nằm
trong `$_SESSION`; cookie sessions bị gỡ. Khi cutover mọi session cũ bị invalidate —
user bị logout (thông báo trước).

Giữ được: `userdata()`, `set_userdata()`, `unset_userdata()`, `flashdata()`,
`set_flashdata()`, `keep_flashdata()`. Thêm: `has_userdata()`, `tempdata()`,
`set_tempdata()`, `mark_as_flash()`, `mark_as_temp()`.

Break im lặng:

- `userdata('missing')`, `flashdata('missing')` trả **NULL** (2.x trả FALSE).
- **`unset_userdata()` giờ nhận mảng key** — `array('a'=>'')` im lặng ngừng hoạt động;
  phải truyền `array('a')`.
- Flashdata chung namespace với userdata — trùng tên ghi đè nhau.
- **Metadata biến mất:** `session_id`, `ip_address`, `user_agent`, `last_activity` không
  còn là userdata. Dùng `session_id()` và `$this->input->ip_address()`.
- Config: bắt buộc `sess_driver`, `sess_save_path`; gỡ `sess_encrypt_cookie`,
  `sess_match_useragent`, `sess_use_database`, `sess_table_name`; thêm `sess_samesite`.
- Bảng database phải đổi schema: `session_id` → `id` varchar(128), bỏ `user_agent`,
  `user_data` → `data` BLOB, `last_activity` → `timestamp`, thêm `ip_address` varchar(45).
- `MY_Session` phải chuyển sang `application/libraries/Session/` và gần như viết lại.
- `sess_save_path = NULL` fallback sang php.ini — set đường dẫn tường minh.

## 4. Core class — constructor nhận dependency

Fork tiêm dependency vào constructor; override `MY_*` phải nhận và forward cho
`parent::__construct(...)`:

| Class | Constructor mới |
|---|---|
| `CI_Hooks` | `__construct(CI_Config $config)` |
| `CI_URI` | `__construct(CI_Config $config)` |
| `CI_Utf8` | `__construct($charset)` |
| `CI_Security` | `__construct($charset)` |
| `CI_Input` | `__construct(CI_Security &$security)` |

`MY_Input`, `MY_Security`, `MY_URI`, `MY_Utf8`, `MY_Hooks` gọi `parent::__construct()`
không tham số sẽ fatal `ArgumentCountError` trên PHP 7.1+.

Thay đổi core khác:

- `Hooks::_call_hook()` → **`call_hook()`**; `_initialize` gộp vào constructor.
- `Config::_assign_to_config()` gỡ — `$assign_to_config` áp qua `set_item()` trong `CodeIgniter.php`.
- `Router::_set_overrides()` gỡ — mảng `$routing` truyền qua constructor;
  `Router::$directory` mặc định `''`.
- Các method URI 2.x (`_fetch_uri_string`, `_filter_uri`, `_explode_segments`…) thay bằng
  `_set_uri_string()`, `_parse_request_uri()`, `_parse_query_string()`, `_parse_argv()`.
- Dispatcher trả 404 cho: method bắt đầu bằng `_`, method không public,
  **constructor kiểu PHP 4** (`function Foo()`), method trùng trên `CI_Controller`.
  `_remap()` vẫn được tôn trọng.
- `Loader`: library/model trả về `$this` (chainable); model không kế thừa `CI_Model` ném
  `RuntimeException`; va chạm tên model ném `RuntimeException` (2.x gọi `show_error`).
  Thêm `dbutil()`, `dbforge()`, `clear_vars()`, `get_vars()`.
- `CI_Controller`, `CI_Model`, `CI_Loader`, `CI_DB_driver`, `CI_Driver_Library` mang
  `#[AllowDynamicProperties]` (PHP 8.2+). Class riêng của app thì không.

## 5. NULL thay FALSE — break im lặng lớn nhất

Ứng viên nâng cấp 2.x kiểm `=== FALSE` khắp nơi; giờ một số lớn trả **NULL**. Cần đổi
thành NULL-safe (`=== NULL`, `empty()`, `isset()`):

| API | 2.2.6 | Fork |
|---|---|---|
| `input->get/post/cookie` (key thiếu) | `FALSE` | `NULL` |
| `input->post()` không arg, `$_POST` rỗng | `FALSE` | `array()` |
| `input->server()` | trả FALSE nếu thiếu | yêu cầu arg; hành vi mới |
| `uri->segment()`, `rsegment()` (segment thiếu) | `FALSE` | `NULL` (có arg thứ hai vẫn giữ) |
| `session->userdata/flashdata` (key thiếu) | `FALSE` | `NULL` |
| `config->item()`, `config_item()` (key thiếu) | `FALSE` | `NULL` |
| `element()` mặc định `$default` | `FALSE` | `NULL` |
| `->row()`, `->row_array()`, `->row_object()` (rỗng) | `array()` | `NULL` |

**`get_post()` đổi thứ tự ưu tiên:** GET trước POST (2.x: POST trước GET). Hàm tương ứng
hành vi cũ là `post_get()`.

Audit grep:

```
grep -rnE "(post|get|cookie|server|get_post|segment|rsegment|userdata|flashdata|config->item|config_item|element)\([^)]*\)\s*(===?|!==?)\s*(FALSE|'')" application
grep -rnE "row(_array|_object)?\(\)" application
```

## 6. Routing và URI

- **`(:any)` giờ là `[^/]+`** (2.x: `.+` — match cả `/`). Catch-all route dùng `(:any)`
  mà trước đây bắt cả slash sẽ im lặng đổi hành vi → dùng `(.+)` nếu muốn match slash.
- `default_controller` và `404_override` áp **theo từng directory** — mẫu
  `directory/controller` từng chạy "nhờ may mắn" giờ không còn.
- Thêm: `$route['translate_uri_dashes']`, route theo HTTP verb
  (`'x' => array('GET'=>'a/b')`), route callback.
- `uri_protocol` mặc định `'REQUEST_URI'` (2.x: `'AUTO'`; `AUTO` vẫn chạy để tương thích ngược).
- URI programmatic không còn tự chuyển ký tự thành HTML entity — filter segment qua
  `xss_clean()` hoặc escape khi output.
- CLI ignore `url_suffix` và `permitted_uri_chars`.

## 7. Database

- **Kết nối lỗi ném `RuntimeException('Unable to connect to the database.')`** kể cả khi
  `db_debug` tắt — áp dụng cho `$this->load->database()`, `DB()` và autoload database.
  Bọc `try/catch (RuntimeException)` cho chỗ gọi thủ công; đừng autoload DB nếu cần xử lý lỗi.
- `DB($params)` chỉ còn một tham số; `$active_record` / `$query_builder` bị bỏ qua —
  Query Builder luôn nạp.
- Config mới: `dsn`, `port`, `failover`, `save_queries`, `encrypt`, `compress`;
  gỡ `autoinit`; `pconnect` mặc định FALSE; driver mặc định `mysqli`.
- **`stricton` đổi hành vi (break im lặng):** nếu key tồn tại, session `sql_mode` bị viết
  lại. `TRUE` thêm `STRICT_ALL_TABLES`; **`FALSE` chủ động gỡ strict mode** — config cũ
  `stricton = FALSE` trước đây không làm gì, giờ tắt strict mode của MySQL ≥ 5.7 cho
  connection đó. Muốn dùng mặc định server thì **xóa key**.
- Query Builder:
  - `where_in($key, array $values)` có type hint — scalar/NULL ném `TypeError`,
    mảng rỗng ném `InvalidArgumentException` (2.x sinh SQL sai `IN ()`). Guard
    `if ($ids)` trước khi gọi.
  - `where('f', NULL)` → `IS NULL`; `where('f !=', NULL)` → `IS NOT NULL`.
  - `join($table, $cond, $type)` ném `InvalidArgumentException` nếu `$type` không phải
    string; `order_by()` ném nếu direction không phải string.
  - Thêm `having_in` family, `get_compiled_*`, `reset_query`, `group_start/end`,
    `insert_batch`/`update_batch` có `$batch_size`.
- Result: `row()`, `row_array()`, `row_object()` trả NULL khi rỗng — `count($q->row())`
  throw trên PHP 8.
- Lỗi: `_error_message()`, `_error_number()` gỡ → dùng `$this->db->error()` trả
  `array('code','message')`.
- `query()` trả **TRUE** cho write query (tự nhận diện qua `is_write_type`).
- `db_set_charset()`, `load_rdriver()` gỡ.
- Forge: `drop_table($name, $if_exists = FALSE)` — **`IF EXISTS` không còn mặc định**;
  `create_table($name, $if_not_exists)`; `add_column()` nhận AFTER target trong field
  definition (không còn tham số thứ ba).
- Utility/OCI8: `get_cursor()`, `stored_procedure()` gỡ.
- Kết nối DB tự set charset (mysql, mysqli, postgre); **sai `char_set` giờ là lỗi kết nối
  (fatal)** — kiểm tra `char_set`/`dbcollat` trong `database.php`.

## 8. Helpers — thay đổi signature và hành vi

| Helper | Thay đổi |
|---|---|
| url | `redirect($uri, $method='auto', $code=NULL)` — với `auto`, GET redirect dùng **307**, sau POST dùng **303** (2.x luôn 302). `url_title()` Unicode-aware: giữ dấu tiếng Việt khi `UTF8_ENABLED` — slug cần strip dấu thì gọi `convert_accented_characters()` trước. |
| form | `form_open()` chèn input CSRF không còn bọc `<div style="display:none">`. `form_upload($data, $extra)` còn 2 tham số. `set_value($f, $d, $html_escape=TRUE)`. `form_prep()` thành alias của `html_escape`. |
| html | `doctype()` mặc định `'html5'` (2.x: `'xhtml1-strict'`). |
| cookie | `get_cookie($index, $xss=FALSE)`; `set_cookie` — `$expire` mặc định 0, âm để xóa, thêm `$samesite`. |
| text | `highlight_phrase()` mặc định thẻ `<mark>`. |
| captcha | `create_captcha($data)` chỉ nhận array; bỏ `img_path`, `img_url`, `font_path` positional; chỉ PNG. |
| download | `force_download($filename, $data='', $set_mime=FALSE)` — mặc định `Content-Type: application/octet-stream`, cần MIME thật thì truyền `$set_mime=TRUE`. |
| file | `delete_files($path, $del_dir, $htdocs, $_level)` — tham số thứ ba giờ là `$htdocs`. |
| array | `element($item, array $array, $default=NULL)` — default NULL (2.x FALSE); không phải array ném `TypeError`. |
| typography | `auto_typography($str, $reduce_linebreaks)` — **tham số `$strip_js_event_handlers` bị gỡ**; gọi 3 tham số cũ sẽ đổi nghĩa. |
| date | `now($timezone=NULL)`; `standard_date()` dùng hằng `DATE_*` của PHP. |
| inflector | `is_countable()` → `word_is_countable()`. |
| string | `random_string('unique'/'encrypt')` vẫn hoạt động (dùng `random_bytes`). |

## 9. Libraries

- **Encrypt → Encryption:** fork **không còn ship `Encrypt`**. `$this->load->library('encrypt')`
  fail. Output **không tương thích** với `Encrypt::encode()` (2.x dùng `MCRYPT_RIJNDAEL_256`
  — không phải AES, OpenSSL không đọc được). Re-encrypt dữ liệu cũ cần mcrypt trên PHP cũ
  hoặc phpseclib. `Encryption` cần `encryption_key` (rỗng thì library từ chối hoạt động).
- **Sha1 library gỡ** → dùng `sha1()` / `hash()`.
- **Form_validation:**
  - `set_rules()` rules rỗng/thiếu ném exception (`BadMethodCallException`/`RuntimeException`).
  - Rule `xss_clean` không còn là method của Form_validation — chỉ chạy nếu load Security helper.
  - Lang key **bắt buộc prefix `form_validation_`**; bỏ fallback không prefix.
  - Message dùng `{field}`/`{param}` (`%s` vẫn hoạt động).
  - Thêm rule `alpha_numeric_spaces`, `differs`, `in_list`, `greater_than_equal_to`,
    `less_than_equal_to`, `valid_mac`, `is_array`; method `has_rule()`, `error_array()`,
    `reset_validation()`, `set_data()`; `run($config, &$data)`.
- **Email:** `validate` mặc định **TRUE**; `send($auto_clear=TRUE)` — thành công thì **tự
  xóa tham số** (dùng `send(FALSE)` nếu gửi lại cùng message); `initialize()` gọi `clear()`
  trước — đừng gọi sau khi đã build message. Thêm `smtp_keepalive`, `dsn`.
- **Pagination:** tag mặc định không còn `&nbsp;`; `uri_segment` mặc định 0 (auto);
  thêm `attributes`, `reuse_query_string`, `data_page_attr`; `anchor_class` vẫn hoạt động;
  `create_links()` trả `''` khi chỉ một trang. Thêm `pagination_lang.php`.
- **Upload:** `initialize($config, $reset=TRUE)` reset mọi property mỗi lần gọi; thêm
  `min_width`, `min_height`, `detect_mime`, `file_ext_tolower`; `data($index)`.
- **Cache:** thêm driver `redis`, `apcu`, `wincache`; `save($id,$data,$ttl,$raw)`;
  thêm `increment`, `decrement`, `get_loaded_driver()`. Cache file format giữ nguyên.
- **Cart, Javascript:** fork giữ lại (changelog nói gỡ nhưng code còn — xem README mục 2).
- **Migration:** `migration_type` mặc định **`'timestamp'`** — file migration 2.x đặt tên
  `001_name.php` cần set `migration_type='sequential'` để tiếp tục chạy.
- **Xmlrpc/Table/Zip:** nhiều method protected giờ là protected (gọi trực tiếp sẽ fail);
  `Table::__construct($config)`.

## 10. Config — merge thay vì ghi đè

`config.php`:

| Key | Thay đổi |
|---|---|
| `uri_protocol` | `AUTO` → `REQUEST_URI` |
| `allow_get_array`, `global_xss_filtering`, `standardize_newlines`, `rewrite_short_tags` | **gỡ** — không còn tác dụng |
| `log_filename` | mới; `log_file_extension` còn như fallback deprecated; thêm `log_file_permissions` |
| `composer_autoload`, `error_views_path`, `cache_query_string` | mới |
| `cookie_httponly`, `cookie_samesite` | mới |
| `csrf_regenerate` (TRUE), `csrf_exclude_uris` | mới |
| `sess_*` | xem mục 3 |
| `encryption_key` | dùng cho Encryption library |

- `database.php`: xóa `$active_record`, `$query_builder` (không còn trong file mặc định).
- `constants.php`: thêm `defined()` guards, `SHOW_DEBUG_BACKTRACE`, hằng `EXIT_*`;
  **`DIR_WRITE_MODE` mặc định 0777 → 0755** — không copy blind, phải merge.
- Thay `mimes.php`, `user_agents.php` (và tùy ý `smileys.php`, `foreign_chars.php`,
  `doctypes.php`) bằng bản fork, trừ khi app đã customize.
- `autoload.php`: thêm `$autoload['drivers']`.
- File mới: `memcached.php` (Cache driver memcached).

## 11. Bảo mật

1. **Mất lớp lọc input toàn cục.** 2.2.6 `Input::_sanitize_globals()` làm 4 việc: unset
   registered globals, chặn "Disallowed Key Characters" (exit), clean UTF-8, strip control
   characters khỏi `$_GET`/`$_POST`/`$_COOKIE`. Fork **không làm gì** trong số đó;
   `$_SERVER['PHP_SELF']` không còn `strip_tags`. Cần tự validate input (type, length,
   charset) và escape đầu ra bằng `html_escape()`.
2. **XSS:** `global_xss_filtering` chết. XSS filtering chỉ chạy khi truyền `$xss_clean=TRUE`
   tường minh. Rule `xss_clean` của Form_validation cần load Security helper.
3. **CSRF:**
   - Verify chuyển từ constructor `Input` sang `Security`; chỉ kiểm POST; so sánh token
     bằng `hash_equals`; bỏ qua CLI.
   - Lỗi CSRF trả **403** (trước là 500).
   - **CSRF cookie đặt `SameSite=Strict`** — callback cross-site POST (IPN cổng thanh toán,
     SSO, webhook) mất cookie → thêm URI vào `csrf_exclude_uris`.
   - `csrf_regenerate=TRUE` xoay token mỗi POST — post AJAX song song có thể fail;
     cân nhắc đặt FALSE.
4. **Cookie:** thêm `cookie_httponly`, `cookie_samesite`, `sess_samesite`.
5. **Output cache, session, file permission** chặt hơn — kiểm `application/cache` và
   session directory có ghi được không.

## 12. Ghi chú upgrade chính thức trong các repo

- 2.x → 3.0: `codeigniter-3.1.13/user_guide/installation/upgrade_300.html` (21 bước) và
  `hoangkim28-codeigniter/user_guide_src/source/installation/upgrade_300.rst`.
- 3.0 → 3.1.x: `upgrade_301.rst … upgrade_3114.rst`. Các bước liên quan nếu đi qua 3.1.13:
  - 3.0.2: `constants.php` mới với `defined()` guard.
  - 3.0.3: auto-detect `base_url` dùng IP server.
  - 3.1.0: PHP 5.6+ khuyến nghị; driver `odbc` không dùng Query Builder/`escape()`.
  - 3.1.2: widen `ci_sessions.id` → `varchar(128)`.
  - 3.1.10: `is_countable()` → `word_is_countable()`.
  - 3.1.9/3.1.11/3.1.12: thay `mimes.php` (và `user_agents.php`).
  - Các bản còn lại: chỉ "thay `system/`".
- 3.1.x → fork: `upgrade_320.rst` (15 bước — tóm tắt trong [UPGRADE_FROM_3.1.13.md](UPGRADE_FROM_3.1.13.md)).
  Lưu ý: mục nào ghi "removed" (Email helper, Cart, `form_prep`…) cần đối chiếu code —
  fork đã khôi phục nhiều mục (README mục 2).

## 13. Checklist thực hiện

### A. Môi trường và entry point (blocking)
1. PHP ≥ 5.4.8; nhắm 8.1–8.4 và test trên đó.
2. Chuyển `mysql` → `mysqli`; xóa mọi gọi trực tiếp `mysql_*` trên `$this->db->conn_id`.
3. Thay `index.php`, áp lại `$system_path`/`$application_folder`/`$view_folder`; xóa dùng `EXT`.
4. Xóa `system/` cũ trước khi cài bản mới (copy đè để lại file rác).
5. Set `base_url` tường minh; set `ENVIRONMENT` qua `CI_ENV`.

### B. Đổi tên cơ học (xem mục 2)
6. Đổi tên controller/model/library/driver/`MY_*` → Ucfirst (sai case = 404 im lặng trên Linux).
7. Di chuyển `application/errors/*` → `views/errors/html/` + copy `errors/cli/`.
8. Di chuyển `[MY_]Log.php` → `application/core/`.
9. Di chuyển `MY_Session` → `application/libraries/Session/` và viết lại.
10. Gỡ `$autoload['core']`.
11. `database.php`: xóa `$active_record`/`autoinit`, set `dbdriver=mysqli`.

### C. Merge config (mục 10)
12. Merge `config.php` — thêm key mới, xóa key gỡ; đặc biệt xét lại `stricton`.
13. Merge `constants.php` (`SHOW_DEBUG_BACKTRACE`, `EXIT_*`, `DIR_WRITE_MODE`).
14. Thay `mimes.php`, `user_agents.php`.
15. Nếu dùng Migration: `migration_type='sequential'`.

### D. Session (mục 3)
16. Chọn driver; với database tạo schema `ci_sessions` mới.
17. Thay mọi `userdata('session_id'|'ip_address'|'user_agent'|'last_activity')`.
18. Sửa `unset_userdata(array('a'=>''))` → `unset_userdata(array('a'))`.
19. Kiểm tra va chạm tên userdata/flashdata.
20. Thông báo forced re-login cho user.

### E. Input, URI, bảo mật (mục 5, 6, 11)
21. Đổi mọi so sánh `=== FALSE` trên input/uri/session/config/row sang NULL-safe.
22. Rà lại mọi `get_post()` — giờ ưu tiên GET.
23. XSS: escape đầu ra; gỡ rule `xss_clean` hoặc load Security helper.
24. Thêm input validation thay cho lớp lọc đã gỡ.
25. Với CSRF: thêm webhook/IPN/SSO vào `csrf_exclude_uris`; quyết định `csrf_regenerate`.
26. Routes: đổi `(:any)` → `(.+)` nếu cần match slash; test `default_controller`/404 theo directory.

### F. Database (mục 7)
27. Guard `where_in` family: chỉ truyền array, bỏ qua array rỗng.
28. Thay `_error_message()`/`_error_number()` → `error()`.
29. Rà lại return type của `query()` với write query (TRUE).
30. Xét lại `stricton` (xóa key nếu muốn mặc định server).
31. `drop_table($t)` dựa vào `IF EXISTS` → `drop_table($t, TRUE)`.
32. `add_column` AFTER target vào field definition.
33. Bật `db_debug` ở dev; bọc `try/catch` quanh `load->database()`.

### G. Libraries và helpers (mục 8, 9)
34. Email: test `validate=TRUE`; dùng `send(FALSE)` nếu gửi lại; không `initialize()` sau build.
35. Form_validation: xóa `set_rules` rỗng; cập nhật lang key prefix; dùng `{field}`.
36. Pagination: style lại markup; kiểm `uri_segment`.
37. `encrypt` → `encryption`; lập kế hoạch re-encrypt dữ liệu cũ (Rijndael-256 không đọc bằng OpenSSL).
38. `force_download` cần MIME thật → `$set_mime=TRUE`.
39. Sửa gọi 3 tham số `auto_typography`; `form_upload($n,$v,$extra)` → `form_upload($n,$extra)`.
40. Slug tiếng Việt: `convert_accented_characters()` trước `url_title()`.
41. Rà `redirect()` sau POST (303), mặc định `doctype()`, `highlight_phrase()` `<mark>`.

### H. Override core class (mục 4)
42. Sửa constructor `MY_Input`, `MY_Security`, `MY_URI`, `MY_Utf8`, `MY_Hooks`.
43. `$EXT->_call_hook()` → `call_hook()`.
44. Kiểm tra `load_class($c, 'libraries', 'MY_')` (tham số thứ ba đổi nghĩa).

### I. Vấn đề PHP 7/8 mà CI không tự sửa
45. Constructor kiểu PHP 4 (`function Foo()`) → `__construct`.
46. Function đã gỡ/deprecated: `each()`, `create_function`, `split`, `ereg*`, `mysql_*`,
    `mcrypt_*`, `get_magic_quotes_gpc`, `$HTTP_RAW_POST_DATA`.
47. Dynamic properties trên class riêng deprecated trên PHP 8.2 (chỉ 5 core class có attribute).
48. Short tag `<? … ?>` phụ thuộc php.ini (`rewrite_short_tags` đã gỡ); `<?=` vẫn ổn.

## 14. Điểm break im lặng cần test riêng

- `(:any)` không còn match slash.
- So sánh `=== FALSE` trên Input/URI/Session/config/row.
- Thứ tự `get_post()` đổi.
- `stricton => FALSE` giờ tắt strict SQL mode.
- Không còn XSS filtering/lọc input toàn cục.
- `url_title()` giữ Unicode (dấu tiếng Việt còn trong slug).
- `force_download()` MIME `octet-stream`.
- `DIR_WRITE_MODE` 0755.
- `send()` xóa tham số Email sau khi gửi.
- CSRF cookie `SameSite=Strict` chặn cross-site POST callback.
- Cutover: output cache và session cũ vô hiệu.
- Chữ hoa tên file trên Linux.
- Migration default đặt tên theo timestamp.
- `redirect()` là 303/307, không còn 302.

## 15. Audit grep tổng hợp

```
grep -rnE "\bEXT\b|_call_hook|_error_message|_error_number|sess_(encrypt|use_database|match_useragent)" application
grep -rnE "(post|get|cookie|server|get_post|segment|rsegment|userdata|flashdata|config->item|config_item)\([^)]*\)\s*(===?|!==?)\s*(FALSE|'')" application
grep -rnE "where_in|where_not_in" application
grep -rnE "xss_clean|global_xss|encrypt->|sha1->|load->library\('(encrypt|sha1)" application
grep -rn "(:any)" application/config/routes.php
grep -rnE "function [A-Z][a-zA-Z_]*\(" application
grep -rnE "\b(each|create_function|split|ereg|mysql_)\b" application
```

## 16. Hạn chế của tài liệu này

- Static analysis trên đĩa, chưa chạy PHP hay test suite của fork trên môi trường thật.
- Chưa diff `user_guide/` HTML của 3.1.13 với `.rst` của fork cho `upgrade_300`.
- Chưa xác minh từng polyfill trong `system/core/compat/` (hash, mbstring, password, standard).
