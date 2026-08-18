# Reflection

Anti-pattern em dễ gặp nhất là xem `VACUUM` như toàn bộ chiến lược dọn
dẹp lakehouse. Khi pipeline ghi song song hoặc bị lỗi giữa chừng, các file
Parquet đã tạo nhưng chưa được commit vào Delta log trở thành orphan. Chúng
không xuất hiện trong lịch sử bảng và Delta `VACUUM` không nhìn thấy chúng,
nên chi phí lưu trữ vẫn tăng dù dashboard nói rằng maintenance đã chạy.

NB6 đã cho thấy khác biệt này: phải đối chiếu file thực trên storage với các
file đang được transaction log tham chiếu, chỉ xoá các orphan đã quá ngưỡng
an toàn, rồi kiểm tra lại. Với Iceberg cũng tương tự: `expire_snapshots` chủ
yếu xử lý metadata; cần quét orphan manifests/data files riêng. Vì vậy đội em
cần lịch maintenance có quan sát trước/sau về số file, byte thu hồi và cảnh
báo orphan, thay vì chỉ chạy `VACUUM` hoặc expiry theo lịch.
