#!/bin/bash -e
# Chỉ seed dữ liệu mẫu khi kho dữ liệu còn trống.
#
# reset-db.sh gọi spamdb.py --drop-db, tức là XOÁ SẠCH rồi tạo lại. Chạy nó ở
# mỗi lần khởi động thì mọi tài khoản người thật đăng ký đều biến mất sau lần
# deploy kế tiếp. Với /seeded nằm trên volume, dữ liệu phải sống sót — nên chỉ
# seed lần đầu, khi thư mục thật sự chưa có gì.
#
# Đặt SEED_DB=force để cố ý dựng lại dữ liệu mẫu (dùng khi muốn dọn demo).

# ĐỪNG đổi tên dấu này theo thương hiệu. Dấu nằm TRONG volume dữ liệu: đổi tên thì
# lần deploy kế tiếp không thấy dấu cũ, script coi như kho còn trống và seed lại —
# tức XOÁ SẠCH mọi tài khoản người thật. Đây là tên tệp nội bộ, không ai nhìn thấy.
MARKER=/seeded/.9kings-seeded

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
  rm -f "$MARKER"
elif [ -f "$MARKER" ]; then
  echo "seed-once: đã seed trước đó ($(cat "$MARKER")) — giữ nguyên dữ liệu."
  exit 0
fi

/scripts/reset-db.sh
date -Iseconds > "$MARKER"
echo "seed-once: đã seed xong."
