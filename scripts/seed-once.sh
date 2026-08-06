#!/bin/bash -e
# Chỉ seed dữ liệu mẫu khi kho dữ liệu còn trống.
#
# reset-db.sh gọi spamdb.py --drop-db, tức là XOÁ SẠCH rồi tạo lại. Chạy nó ở
# mỗi lần khởi động thì mọi tài khoản người thật đăng ký đều biến mất sau lần
# deploy kế tiếp. Với /seeded nằm trên volume, dữ liệu phải sống sót — nên chỉ
# seed lần đầu, khi thư mục thật sự chưa có gì.
#
# Đặt SEED_DB=force để cố ý dựng lại dữ liệu mẫu (dùng khi muốn dọn demo).

# Dấu nằm TRONG volume dữ liệu. Đổi tên hạ tầng 9kings→hungkings (2026-08-06): dấu
# cũng đổi theo, NHƯNG vẫn nhận diện dấu CŨ để volume đã migrate (mang dấu cũ) KHÔNG
# bị coi là kho trống rồi seed đè = mất sạch tài khoản. Nếu đổi tên hạ tầng lần nữa,
# lặp đúng khuôn này: thêm dấu mới, giữ nhận diện dấu cũ ít nhất một vòng deploy.
MARKER=/seeded/.hungkings-seeded
OLD_MARKER=/seeded/.9kings-seeded

wait_for_mongo() {
  # Volume trống thì mongod phải khởi tạo kho dữ liệu mới, lâu hơn hẳn so với
  # mở một kho có sẵn — chờ theo trạng thái thật thay vì đoán bằng sleep.
  for _ in $(seq 1 60); do
    if mongosh --quiet --eval 'db.adminCommand("ping")' >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "seed-once: mongod không phản hồi sau 120 giây" >&2
  return 1
}

wait_for_mongo

if [ "$SEED_DB" = "force" ]; then
  echo "seed-once: SEED_DB=force — dựng lại dữ liệu mẫu, XOÁ mọi dữ liệu hiện có."
  rm -f "$MARKER" "$OLD_MARKER"
elif [ -f "$MARKER" ] || [ -f "$OLD_MARKER" ]; then
  echo "seed-once: đã seed trước đó — giữ nguyên dữ liệu."
  # Bảo đảm dấu MỚI tồn tại để lần sau nhận diện thẳng, không phụ thuộc dấu cũ.
  [ -f "$MARKER" ] || cp -a "$OLD_MARKER" "$MARKER" 2>/dev/null || date -Iseconds > "$MARKER"
  exit 0
fi

/scripts/reset-db.sh
date -Iseconds > "$MARKER"
echo "seed-once: đã seed xong."
