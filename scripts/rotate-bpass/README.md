# Xoay `user.password.bpass.secret` mà không làm hỏng mật khẩu ai

## Vì sao cần biết chuyện này

Ghi chép cũ nói "đổi secret = mọi mật khẩu hiện có thành vô hiệu". **Sai.**
Khoá đó không phải thành phần của bcrypt, nó chỉ là **khoá AES bọc ngoài** hash bcrypt
(`modules/security/src/main/PasswordHasher.scala`):

```
bpass = salt(16 byte) ++ AES/CTS/NoPadding(iv = salt, key = secret)( bcryptRaw(sha512(pw), salt) )
        tổng đúng 39 byte; lila từ chối mọi độ dài khác (PasswordHasher.parse)
```

AES đảo ngược được, và `iv` chính là 16 byte đầu đã nằm sẵn trong bản ghi. Nên
**giải bằng khoá cũ rồi mã lại bằng khoá mới** cho ra hash tương đương tuyệt đối:
không cần biết mật khẩu của ai, không ai phải đặt lại mật khẩu.

Khoá này chỉ được dùng ĐÚNG MỘT CHỖ trong toàn bộ lila (`security/Env.scala:58` →
`PasswordHasher`). Đã kiểm: TOTP không dùng nó, OAuth không dùng nó. Phạm vi ảnh
hưởng vì thế đúng bằng trường `bpass` của collection `user4`.

## Chạy

Cần một JVM — bản image demo có sẵn JDK đầy đủ (`javac` nằm trong container), nên
làm thẳng trong đó là chắc nhất: dùng đúng bản Java mà lila dùng, khỏi tự viết lại
CTS (ciphertext stealing) bằng ngôn ngữ khác rồi sai lệch âm thầm.

```sh
docker cp Rotate.java 9kings-web:/tmp/ && docker exec 9kings-web sh -lc 'cd /tmp && javac Rotate.java'

# 1. SAO LƯU TRƯỚC — đây là đường lùi duy nhất
docker exec 9kings-web mongosh --quiet lichess dump.js > before.tsv

# 2. Sinh bản đã xoay (chưa ghi gì vào DB)
docker exec 9kings-web sh -lc 'cd /tmp && java Rotate "$KHOA_CU" "$KHOA_MOI" < before.tsv > after.tsv'

# 3. Kiểm ĐẢO NGƯỢC: xoay ngược bản mới phải ra đúng bản gốc từng byte
docker exec 9kings-web sh -lc 'cd /tmp && java Rotate "$KHOA_MOI" "$KHOA_CU" < after.tsv | diff - before.tsv'

# 4. Ghi vào MongoDB bằng bulkWrite (BinData(0, "<base64>")), rồi dump lại và diff với after.tsv
```

`dump.js` chỉ có một dòng:
```js
db.user4.find({bpass:{$exists:true}},{bpass:1}).forEach(u => print(u._id + "\t" + u.bpass.toString("base64")))
```

## Thứ tự BẮT BUỘC khi xoay

DB và container phải lật cùng lúc; giữa hai thời điểm đó **không ai đăng nhập được**.
Rút ngắn quãng đó bằng cách kéo image TRƯỚC:

1. Sửa `deploy/.env` (khoá mới) → build image → **`docker pull` cưỡng bức** trên VPS
2. Xoay DB
3. Deploy ngay

Muốn chắc việc xoay có hiệu lực thật chứ không phải chạy không: sau bước 2 và
trước bước 3, thử đăng nhập — **phải nhận 401**. Container lúc đó còn dùng khoá cũ.
Không có phép thử phủ định này thì một lần xoay hỏng vẫn "đậu" y hệt một lần xoay đúng.

## Bẫy

- **Sinh khoá bằng `openssl rand -base64 32`** (256-bit). lila chỉ nhận 128/192/256-bit
  sau khi giải base64; độ dài khác là `IllegalArgumentException` lúc khởi động.
- **Đừng truyền khoá qua tham số dòng lệnh trên máy nhiều người dùng** — nó hiện trong `ps`.
  Ở đây chép qua file `chmod 600` rồi `docker cp`.
- **`git show --stat` không chứng minh nội dung vào commit.** Kiểm bằng `git show HEAD:<file>`.
- **Bản sao lưu `before.tsv` là hash được bảo vệ bằng khoá CÔNG KHAI của upstream.**
  Coi nó như dữ liệu nhạy cảm và xoá khi đã hết cần đường lùi.
