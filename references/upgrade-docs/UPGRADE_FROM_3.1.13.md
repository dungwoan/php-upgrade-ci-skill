> Bundled copy from the team's upgrade-ci docs, 2026-10-26. Source of truth: the original docs folder; re-copy to refresh.

# Nâng cấp CodeIgniter 3.1.13 → Fork "3.4.5" (hoangkim28)

Tài liệu dành cho application đang chạy CodeIgniter 3.1.13 chính thức và muốn nâng
lên fork `hoangkim28/codeigniter` (nhãn `CI_VERSION = '3.4.5'`, repo
<https://github.com/hoangkim28/codeigniter>).

> **Lưu ý:** "3.4.5" là community fork xây trên nhánh 3.2.0-dev chưa phát hành, không phải
> bản chính thức của BCIT. Xem [README.md](README.md) mục 2 trước khi bắt đầu.

## Tổng quan phạm vi

Fork chỉ khác 3.1.13 ở mức hệ thống file: `system/` có 71 file thay đổi, 1 file thêm
(`Cache_apcu.php`), 8 file/gộp thư mục gỡ bỏ (`Encrypt.php`, `sqlite/`,
`SessionHandlerInterface.php`, `Javascript/index.html`). Application nâng cấp in-place:
thay `system/` + `index.php`, merge config, sửa code theo checklist dưới đây.

## Yêu cầu môi trường

- PHP ≥ 5.4.8 (fork khai báo 5.4.8+ trong `composer.json`, readme tuyên bố 5.4–8.x,
  khuyến nghị 8.4+). 3.1.13 hỗ trợ thấp hơn (5.3.7) — app vẫn trên PHP 5.3 không nâng được.
- Trên PHP 8.4+, `index.php` mới của fork thiết lập `error_reporting` phù hợp; nên thay cả
  `index.php` để tránh ồn deprecation.

## Breaking changes chính

### 1. Core class constructor đổi — fatal nếu có MY_* override

Fork tiêm dependency vào constructor các core class:

| Class | Constructor mới |
|---|---|
| `CI_Hooks` | `__construct(CI_Config $config)` |
| `CI_URI` | `__construct(CI_Config $config)` |
| `CI_Utf8` | `__construct($charset)` |
| `CI_Security` | `__construct($charset)` |
| `CI_Input` | `__construct(CI_Security &$security)` |

`MY_Input`, `MY_Security`, `MY_URI`, `MY_Utf8`, `MY_Hooks` định nghĩa `__construct()`
và gọi `parent::__construct()` không tham số sẽ fatal `ArgumentCountError` trên PHP 7.1+.
`Hooks` giờ được tạo sau `Config` nên hook `pre_system` chạy sau khi config load xong.

### 2. Input: không còn lọc toàn cục (im lặng thay đổi hành vi)

Các method `_sanitize_globals()`, `_clean_input_data()`, `_clean_input_keys()` bị gỡ.
`$_GET`, `$_POST`, `$_COOKIE` không còn được UTF-8 clean, strip invisible characters,
hay chặn "Disallowed Key Characters". `$_SERVER['PHP_SELF']` không còn `strip_tags`.

- `$config['global_xss_filtering']` không còn tác dụng; `xss_clean` mặc định FALSE ở mọi nơi.
- `MY_Input` override `_clean_input_data()` / `_sanitize_globals()` thành dead code.
- `get_post()` / `post_get()` trả về giá trị khác NULL đầu tiên (thay vì kiểm `isset`).

Hệ quả bảo mật: mọi điểm echo input trực tiếp (nhất là `PHP_SELF`, cookie, GET key)
trở thành lỗ XSS tiềm ẩn. Cần audit và escape đầu ra bằng `html_escape()`.

### 3. Database: kết nối lỗi ném RuntimeException

- `db_connect()` / `initialize()` thất bại ném `RuntimeException` thay vì trả FALSE;
  sai `char_set` trong config cũng tính là lỗi kết nối.
- `db_set_charset()` và `load_rdriver()` bị gỡ.
- `DB()` luôn nạp Query Builder; tham số thứ ba `$query_builder` của
  `$this->load->database($params, $return, $query_builder)` bị gỡ, biến `$query_builder`
  trong `database.php` bị bỏ qua.
- Query Builder: `where_in`, `or_where_in`, `where_not_in`, `or_where_not_in` yêu cầu
  `array $values`; mảng rỗng hoặc key rỗng ném `InvalidArgumentException` (3.1.13 tạo SQL
  sai `IN ()`). `join()` / `order_by()` ném nếu type/direction không phải string.
- `escape_identifiers()` thêm tham số `$split = TRUE` — override cần cập nhật.
- Driver `sqlite` (v2) bị gỡ; dùng `sqlite3` hoặc `pdo` + `sqlite`.
- `ci_sessions` dùng driver database: xét lại format nếu đã lưu trữ.

### 4. Session, Encrypt, Redis cache

- **`Encrypt` library bị gỡ** — chuyển sang `Encryption` (không tương thích định dạng;
  dữ liệu mã hóa cũ bằng MCrypt/Rijndael-256 phải re-encrypt).
- Redis cache driver đổi định dạng lưu trữ (hash với `__ci_type`/`__ci_value` thay vì
  string). Key cũ từ 3.1.13 sai kiểu dữ liệu → **flush cache Redis khi cutover**.
- Redis session `save_path` chấp nhận `unix://path` và `tls://host:port`.
- `libraries/Session/SessionHandlerInterface.php` không còn được ship (PHP 5.4+ có sẵn).

### 5. Form_validation

- `set_rules()` với rules rỗng/thiếu ném `RuntimeException` / `BadMethodCallException`
  (3.1.13 là no-op vô hại).
- `run()` trả FALSE sớm khi có lỗi; chỉ ghi `$_POST` khi validation pass (3.1.13 ghi cả hai trường hợp).
- Bỏ fallback lang key thiếu prefix `form_validation_`.
- `prep_url()` không còn coi `'http://'` là chuỗi rỗng.
- Thêm rule `valid_mac`, validation mảng, `run($config, &$data)`.

### 6. Helper và Output

- `create_captcha()` chỉ nhận array, chỉ xuất PNG; thêm `data:` URI, `img_alt`, `img_class`.
- `form_upload($name, $extra)` — bỏ tham số giữa.
- `doctype()` mặc định đổi sang `html5`.
- `set_cookie()` / `Input::set_cookie()`: `$expire` mặc định `0` (session cookie), giá trị
  âm để xóa cookie; thêm `$samesite`.
- `force_download()` gửi header RFC 6266 (`filename*` UTF-8).
- `get_dir_file_info($dir, FALSE)` trả key theo relative path.
- `Output::_display($output = NULL)` — truyền `''` để dùng final_output phải đổi sang `NULL`.
- **Output cache đổi format key** (dùng `slash_item('index_page')`) → xóa `application/cache`.

### 7. Logging

Nhiều `log_message('debug', ...)` trong core đổi thành `'info'` (Config, Output, Utf8,
Input). Với `log_threshold = 2` sẽ không thấy "Config file loaded", "Total execution time"…
Nâng threshold lên 3 hoặc 4. Thêm `$config['log_filename']` (mới);
`log_file_extension` vẫn hoạt động như fallback.

### 8. Loader và view

- `$this->load->view()` xếp chồng biến: view lồng nhau kế thừa biến của view cha.
  App dùng `isset($var)` kiểm tra biến "không tồn tại" trong nested view có thể đổi hành vi.
- `$this->load->model()` luôn kiểm `is_subclass_of($model, 'CI_Model')` — model không
  kế thừa `CI_Model` sẽ throw.

### 9. Router

- `Router::$directory` mặc định `''` (3.1.13 là unset/NULL). Code dùng
  `isset($router->directory)` hoặc so sánh NULL cần sửa.
- Thêm `Router::$uri` (public).

## Checklist nâng cấp

### Trước khi bắt đầu
1. Backup mã nguồn và database; đưa site về maintenance.
2. Xác định PHP mục tiêu (≥ 5.4.8; nên 8.1–8.4) và test trên đó.
3. Pin fork theo commit/tag cụ thể (không pin nhánh `develop`).
4. Grep app các mục sau trước khi thay `system/`:

```
grep -rnE "class MY_(Hooks|URI|Input|Security|Utf8)" application
grep -rnE "load->library\('encrypt'\)|encrypt->" application
grep -rnE "where_in\(|or_where_in\(|where_not_in\(" application
grep -rnE "load->database\([^)]*,[^)]*,|\$query_builder" application
grep -rnE "db_set_charset|load_rdriver|stmt_id|curs_id|stored_procedure|get_cursor" application
grep -rnE "global_xss_filtering|allow_get_array|standardize_newlines" application
grep -rnE "form_upload\(|create_captcha\(" application
grep -rnE "_display\(''\)|router->directory" application
grep -rn "sqlite" application/config/database.php
```

### Thực hiện nâng cấp
5. Xóa `system/` cũ rồi thay bằng `system/` của fork (đừng copy đè — file cũ như
   `Encrypt.php`, `sqlite/`, `SessionHandlerInterface.php` phải biến mất).
6. Thay `index.php` (hoặc merge khối `error_reporting` cho PHP 8.4+).
7. Merge config: `config.php` (thêm `log_filename`, xóa option đã gỡ), `database.php`
   (xóa `$query_builder`), `mimes.php` (thêm `webp`), `user_agents.php`.
8. Sửa code theo danh sách grep ở trên: bọc try/catch quanh load database, guard
   `where_in` bằng `if ( ! empty($ids))`, chuyển `Encrypt` → `Encryption`, sửa constructor
   `MY_*`.

### Test các điểm break im lặng
9. **Input:** audit mọi chỗ dựa vào lọc input toàn cục; escape đầu ra bằng
   `html_escape()` hoặc `$this->input->post('x', TRUE)`.
10. **Session:** test login/logout/`sess_regenerate`; với Redis session kiểm lại format
    `sess_save_path`.
11. **Redis cache:** flush database cache.
12. **Logging:** nâng `log_threshold` lên 3/4 nếu phụ thuộc dòng debug-level cũ.
13. **Output cache:** xóa `application/cache`.
14. **Email:** gửi test — `validate` mặc định TRUE, địa chỉ trước đây lọt qua giờ sẽ fail.
15. **Query Builder:** regression mọi query dùng `join()` custom type, `order_by()`
    direction NULL, `where_in`.
16. **Charset:** đảm bảo `char_set` trong `database.php` server chấp nhận (vd `utf8mb4`);
    sai giá trị giờ là fatal.
17. **Oracle/OCI8:** cursor và stored procedure phải viết lại bằng `oci_new_cursor()`
    với `$this->db->conn_id`.
18. **Code extends framework:** subclass `CI_Xmlrpc`, `CI_Profiler`, `CI_DB_driver` cần
    đối chiếu property/signature mới.

### Sau nâng cấp
19. Chạy toàn bộ test suite trên PHP mục tiêu; theo log `E_DEPRECATED`.
20. Bật lại site; giữ `system/` và `index.php` cũ để rollback.

## Điểm cần kiểm chứng khi fork có runtime

Phân tích này là static analysis (không chạy PHP trên máy phân tích). Cần verify trên
môi trường thật: tương thích PHP thực tế của fork, hành vi mysqli khi charset fail
(`mysqli_driver.php` nhánh charset-failure dùng `$this->db->db_debug` — nghi lỗi upstream),
và PHPUnit suite của fork.
