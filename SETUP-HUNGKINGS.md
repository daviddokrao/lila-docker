# HungKings — ghi chú dựng môi trường

Fork của [lichess-org/lila-docker](https://github.com/lichess-org/lila-docker), dựng full stack Lichess
làm nền cho HungKings. Chưa sửa gì về sản phẩm — mọi thay đổi dưới đây chỉ để môi trường chạy được.

## Repo layout

> Thư mục trên đĩa vẫn tên `9Kings` và **các đường dẫn dưới đây là đường dẫn THẬT** — đừng
> "sửa cho khớp thương hiệu", sửa là tài liệu sai. Cùng lý do với tên hạ tầng `9kings` trong
> `deploy/deploy.json`: đó là định danh nội bộ, không phải tên thương hiệu.

```
C:\PROJECTS\9Kings\lila-docker\      # orchestration (fork daviddokrao/lila-docker)
  repos\lila\                        # server chính, Scala 3 (fork daviddokrao/lila)
  repos\lila-ws\                     # websocket server (fork daviddokrao/lila-ws)
  repos\lila-db-seed\                # dữ liệu mẫu (fork daviddokrao/lila-db-seed)
  repos\lila-fishnet\                # hàng đợi Stockfish khi chơi với máy (fork daviddokrao/lila-fishnet)
```

Mỗi repo có 2 remote: `origin` = fork của mình, `upstream` = lichess-org (để sync ngược).

## Chạy

```bash
docker compose up -d          # khởi động (đã có settings.env/.env sẵn)
docker compose stop           # dừng, giữ nguyên container
docker compose logs -f lila   # xem log compile/run
```

Site: http://localhost:8080 · Mongo Express: http://localhost:8081 · Mailpit: http://localhost:8025

Tài khoản seed: mọi username trong danh sách của `scripts/users.py`, mật khẩu `password`.
Admin: `admin` / `superadmin`. API token dạng `lip_<username>` (vd `lip_bobby`).

Sau khi sửa Scala: `docker compose restart lila`.
Sau khi sửa TS/SCSS: `docker compose run --rm ui /lila/ui/build --debug` (thêm `--watch` để tự build lại).

## Setup đã chạy thủ công (thay cho wizard TUI của lila-docker)

Wizard `./lila-docker start` là TUI tương tác, không chạy được không-tương-tác ở chế độ Advanced
(biến `NONINTERACTIVE` ép về Quick, tức dùng image dựng sẵn và không có source code). Nên các file
`settings.toml` / `settings.env` / `.env` được ghi tay, tương đương lựa chọn Advanced với các service:
base, email, lila-ws-build, mongo-express, stockfish-analysis, stockfish-play.

Các bước setup còn lại đã chạy tay theo đúng thứ tự của script `lila-docker`:
build images → `compose up -d` → build UI → seed DB → tạo index → trophy kinds → `scripts/users.py`.

## Vá lỗi môi trường

### 1. Line endings CRLF (Windows)

Git for Windows đặt `core.autocrlf=true` ở system config, làm shell script trong repo bị checkout
kiểu CRLF; bash trong container báo `$'\r': command not found`. Đã set per-repo:

```bash
git config core.autocrlf false
git config core.eol lf
git rm --cached -r . && git reset --hard   # renormalize working tree
```

### 2. Symlink (Windows)

Repo `lila` có 136 symlink. Không bật Developer Mode và không chạy admin thì git ghi chúng thành file
text chứa đường dẫn đích, làm vỡ UI build (`ui/.build/src/algo.ts`, `ui/test`). Đã set
`core.symlinks=true` cho repo lila và khôi phục bằng git chạy trong container Linux:

```bash
docker run --rm --entrypoint sh -v "C:\PROJECTS\9Kings\lila-docker\repos\lila:/repo" -w /repo alpine/git \
  -c "git config --global --add safe.directory /repo; git checkout -f -- ."
```

Việc này phải lặp lại sau mỗi `git pull`/`checkout` chạm vào symlink, **trừ khi** bật Developer Mode
(Settings → System → For developers) — khi đó git Windows tự tạo được symlink, không cần admin.

### 3. lila-ws không đọc được config — `compose-lila-ws-build.yml`

lila-ws đã lên sbt 2.0.4, mà sbt 2 đổi mặc định `run / fork` thành `true`. Vì vậy entrypoint gốc
`sbt run -Dconfig.file=/lila-ws.conf` truyền option thành **tham số của app** (đứng sau main class)
thay vì JVM option, config bị bỏ qua, lila-ws quay về mặc định Redis `127.0.0.1` và crash.

Đã đổi sang `JAVA_TOOL_OPTIONS=-Dconfig.file=/lila-ws.conf` — mọi JVM đều đọc biến này, kể cả process
fork. Đây là lỗi upstream, nên cân nhắc gửi PR ngược về lichess-org/lila-docker.

### 4. fishnet clients — `compose.yml`

Hai fishnet client trong compose gốc không có API key:

- `fishnet_play` → lila-fishnet: thiếu key thì client gửi header `Authorization: Bearer` rỗng, http4s
  parse fail → 400 và client tự thoát. Đã thêm `KEY=lilafishnetdev` (key phải alphanumeric).
- `fishnet_analysis` → lila: lila xác thực client theo collection `fishnet_client`, key lạ trả 404.
  Đã thêm `KEY=lilafishnetanalysis` và tạo document tương ứng:

  ```js
  db.fishnet_client.insertOne({
    _id: 'lilafishnetanalysis', userId: 'lichess', skill: 'all',
    enabled: true, createdAt: new Date()
  })
  ```

  Document này nằm trong DB nên sẽ mất khi re-seed (`--drop-db`) — cần chèn lại.

## Giấy phép

lila dùng **AGPL-3.0**: nếu HungKings chạy public trên web thì phải công khai source của bản sửa đổi,
kể cả không phân phối binary. Các fork hiện đang public nên đã đáp ứng.
