> Bundled copy from the team's upgrade-ci docs, 2026-10-29. Source of truth: the original docs folder; re-copy to refresh.

# Tổng quan so sánh và lộ trình nâng cấp CodeIgniter

Tài liệu này mô tả khác biệt giữa ba phiên bản CodeIgniter hiện có trong workspace
và chỉ ra lộ trình nâng cấp cho application đang chạy trên hai phiên bản cũ.

## 1. Ba phiên bản trong workspace

| Thư mục | Phiên bản khai báo | Nguồn thực tế | Ghi chú |
|---|---|---|---|
| `codeigniter-2.2.6/` | CI 2.2.6 | bcit-ci/CodeIgniter, tag `2.2.6` | Bản chính thức (BCIT) |
| `codeigniter-3.1.13/` | CI 3.1.13 | bcit-ci/CodeIgniter, tag `3.1.13` | Bản chính thức cuối cùng của BCIT |
| `hoangkim28-codeigniter/` | CI 3.4.5 | Fork cộng đồng, nhánh `develop` | **Không phải bản chính thức** |

Nguồn clone của ba thư mục trên:

| Thư mục | Repo nguồn |
|---|---|
| `codeigniter-2.2.6/` | <https://github.com/bcit-ci/CodeIgniter/tree/2.2.6> |
| `codeigniter-3.1.13/` | <https://github.com/bcit-ci/CodeIgniter/tree/3.1.13> |
| `hoangkim28-codeigniter/` | <https://github.com/hoangkim28/codeigniter> (nhánh `develop`, clone `--depth 1`) |

Trên Packagist, fork này là package `hoangkim28/codeigniter`, phiên bản `v0.2.1` (2026-10-23).

## 2. Cảnh báo quan trọng — "3.4.5" là community fork

Không tồn tại bản phát hành chính thức CodeIgniter 3.2, 3.3 hay 3.4 của EllisLab/BCIT.
`hoangkim28/codeigniter` là fork cộng đồng, xây trên nhánh **3.2.0-dev chưa phát hành**
của upstream (cụ thể là fork của `pocketarc/codeigniter`), với các vá tương thích PHP 8.x.
Những điểm cần biết:

- `CI_VERSION = '3.4.5'` chỉ là một hằng số trong `system/core/CodeIgniter.php:59`,
  không phản ánh bất kỳ bản phát hành chính thức nào.
- `changelog.rst` trong fork đã cũ (dừng ở "3.2.0 – Not Released") và mô tả nhiều mục bị
  *gỡ bỏ* nhưng thực tế fork đã *khôi phục* lại (Cart, Email helper, Smiley helper,
  `form_prep()`, `br()`, `nbs()`, `do_hash()`, `read_file()`, `trim_slashes()`,
  `repeater()`, `standard_date()`, `nice_date()`, `url_title('dash')`,
  `random_string('unique'/'encrypt')`, `Pagination::anchor_class`,
  `Config::system_url()`, `Router::fetch_*()`, `Input::is_cli_request()`).
  **Tin vào code, không tin changelog.**
- `upgrade_320.rst` trong fork ghi `composer require pocketarc/codeigniter` — sai;
  package đúng là `hoangkim28/codeigniter`.
- Git history của fork chỉ có một commit (`b6d67da`) — không truy vết được lịch sử.
  Nên pin theo commit/tag cụ thể, không pin theo nhánh `develop`.

Trước khi nâng cấp production, cần thống nhất với người sở hữu fork ý nghĩa của nhãn
"3.4.5" và phạm vi thay đổi được cover bởi fork này.

## 3. So sánh tổng quan ba phiên bản

| Lĩnh vực | 2.2.6 | 3.1.13 | Fork (3.4.5) |
|---|---|---|---|
| PHP khuyến nghị | 5.2–5.6 | 5.6+ (tối thiểu 5.3.7) | 5.4.8+; readme tuyên bố hỗ trợ đến 8.x; khuyến nghị 8.4+ |
| PHP 8.2+ chạy được | Không (deprecation liên tục) | Có nhưng ồn (thiếu `#[AllowDynamicProperties]`) | Có (đã thêm attribute trên các core class) |
| Core class | `Input`, `Security`, `URI`, `Hooks`, `Utf8` không nhận tham số constructor | Giống 2.x | Constructor nhận dependency (`CI_Config`, `CI_Security`, `$charset`) |
| Query Builder | `DB_active_rec.php` | `DB_query_builder.php`, tắt được bằng `$query_builder` | Luôn bật; `where_in` family yêu cầu `array` |
| Kết nối DB lỗi | Trả về `FALSE`/trang lỗi theo `db_debug` | Giống 2.x | Ném `RuntimeException`; sai charset cũng tính là lỗi kết nối |
| Session | Cookie hoặc database, API `sess_*` cũ | Server-side qua `session_set_save_handler`, driver `files`/`database`/`redis`/`memcached` | Giống 3.1.13 + Redis TLS/unix socket, `sess_samesite` |
| Mã hóa dữ liệu | `Encrypt` library (MCrypt, Rijndael-256) | `Encryption` library (OpenSSL, AES) | Giống 3.1.13; **Encrypt library đã gỡ bỏ hoàn toàn** |
| Lọc input toàn cục | Có (`_sanitize_globals`: UTF-8 clean, strip control chars, "Disallowed Key Characters") | Giống 2.x nhưng `global_xss_filtering` mặc định FALSE | **Đã gỡ bỏ hoàn toàn** — app tự validate |
| CSRF | Có | Có | Chuyển sang `Security::__construct`; lỗi trả HTTP 403; cookie `SameSite=Strict` |
| `(:any)` trong routes | `.+` (match cả `/`) | `.+` | `[^/]+` (không match `/`) |
| `get()`/`post()` khi thiếu key | `FALSE` | `NULL` | `NULL` |
| `get_post()` thứ tự | POST trước GET | GET trước POST | GET trước POST |
| Drivers DB | mysql, mysqli, oci8, odbc, pdo, postgre, mssql, sqlite, sqlsrv | + sqlite3, pdo subdrivers, ibase; còn mysql (legacy) | Gỡ `sqlite` (v2); mysql legacy còn nhưng fatal trên PHP ≥ 7 |
| Cache drivers | apc, file, memcached, dummy | + redis, wincache | + apcu; Redis cache đổi định dạng lưu trữ (hash) |
| Errors pages | `application/errors/` | `application/views/errors/html/` + `errors/cli/` | Giống 3.1.13 |

## 4. Lộ trình khuyến nghị

### Từ 3.1.13 → fork
Nâng cấp in-place: thay `system/` + `index.php`, merge config, xử lý khoảng 15 mục
breaking change. Chi tiết: [UPGRADE_FROM_3.1.13.md](UPGRADE_FROM_3.1.13.md).
Ví dụ đã đi qua bước này, kèm bài học thực tế: [LESSONS_NAMABANK_PHP84.md](LESSONS_NAMABANK_PHP84.md).

### Từ 2.2.6 → fork
Nhảy hai bản chính thức (2.x → 3.x). Có hai lựa chọn:

- **Nâng thẳng một lần** theo [UPGRADE_FROM_2.2.6.md](UPGRADE_FROM_2.2.6.md) —
  ngắn hơn về tổng số bước nhưng rủi ro cao vì phải xử lý đồng thời thay đổi của 3.0
  và của fork.
- **Nâng hai giai đoạn** (khuyên dùng nếu app lớn): trước tiên nâng 2.2.6 → 3.1.13
  theo hướng dẫn chính thức (`user_guide/installation/upgrade_300.html` trong repo
  3.1.13, gồm 21 bước), chạy ổn định, rồi mới nâng 3.1.13 → fork theo tài liệu ở trên.

### Yêu cầu chung cho cả hai lộ trình
1. PHP mục tiêu ≥ 5.4.8 với fork; nên nhắm 8.1–8.4 và test trên đó.
2. Backup mã nguồn + database; chuẩn bị rollback (giữ `system/` và `index.php` cũ).
3. Chạy bộ audit grep trước khi thay bất kỳ thứ gì (có trong từng tài liệu).
4. Xác nhận lại yêu cầu bảo mật đầu vào (input validation) — cả hai đường nâng cấp đều
   mất lớp lọc input toàn cục ở mức fork.

## 5. Nội dung tài liệu

| Tài liệu | Đối tượng |
|---|---|
| [UPGRADE_FROM_2.2.6.md](UPGRADE_FROM_2.2.6.md) | App đang chạy CodeIgniter 2.2.6 |
| [UPGRADE_FROM_3.1.13.md](UPGRADE_FROM_3.1.13.md) | App đang chạy CodeIgniter 3.1.13 |
| [UPGRADE_PHP.md](UPGRADE_PHP.md) | Nâng runtime PHP từ 5.6 hoặc 7.x lên 8.4/8.5, áp dụng cho mọi app CodeIgniter |
| [COMPARE_JACCS_HANMIR.md](COMPARE_JACCS_HANMIR.md) | So sánh core, library và package của hai codebase nội bộ jaccs và hanmir |
| [AI_AGENT_PLAYBOOK_PHP8.md](AI_AGENT_PLAYBOOK_PHP8.md) | **Runbook cho AI agent thực thi** nâng cấp một source kiểu hanmir lên PHP 8 theo đúng cách jaccs đã làm |
| [LESSONS_HANMIR_PHP84.md](LESSONS_HANMIR_PHP84.md) | Kinh nghiệm thực tế khi nâng hanmir lên PHP 8.4 (giữ CI 3.1.9): lỗi chưa được dự đoán, bẫy deploy, việc còn tồn |
| [LESSONS_NAMABANK_PHP84.md](LESSONS_NAMABANK_PHP84.md) | Kinh nghiệm nâng namabank (CI 3.1.9 → fork v0.2.1, PHP 8.4): gate lint phải đọc output, deprecation bị giấu ở nhiều nơi, dọn tính năng chết, kiểm soát đăng nhập, thứ tự DB trước deploy |

Hai tài liệu đầu xử lý phần framework, `UPGRADE_PHP.md` xử lý phần ngôn ngữ và runtime,
`COMPARE_JACCS_HANMIR.md` là phần áp dụng cụ thể cho hai source nội bộ.

Chọn tài liệu theo vai trò:

| Vai trò | Đọc gì |
|---|---|
| AI agent được giao thực thi nâng cấp | `AI_AGENT_PLAYBOOK_PHP8.md` trước tiên, rồi `LESSONS_HANMIR_PHP84.md`; các file khác chỉ đọc khi playbook dẫn chiếu |
| Người lập kế hoạch | `COMPARE_JACCS_HANMIR.md` để nắm hiện trạng, rồi `UPGRADE_PHP.md` để chốt lộ trình |
| Lập trình viên thực thi phần framework | `UPGRADE_FROM_3.1.13.md` hoặc `UPGRADE_FROM_2.2.6.md` tùy phiên bản xuất phát |
| Agent hoặc dev nâng source đã swap sang fork (kiểu namabank) | `LESSONS_NAMABANK_PHP84.md`, đọc kèm `AI_AGENT_PLAYBOOK_PHP8.md` |

## 6. Nguồn tham chiếu trong các repo

- `codeigniter-3.1.13/user_guide/installation/upgrade_300.html` — hướng dẫn chính thức 2.x → 3.0.
- `hoangkim28-codeigniter/user_guide_src/source/installation/upgrade_300.rst … upgrade_320.rst` —
  hướng dẫn chính thức 3.0 → 3.1.x và 3.1.x → 3.2+ (áp dụng cho fork).
- `hoangkim28-codeigniter/user_guide_src/source/changelog.rst` — **đã cũ, cần đối chiếu với code** (xem mục 2).
