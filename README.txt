G-NAVI - CÀI ĐẶT XE BẰNG CÁP USB (WINDOWS)
==========================================

Cách dùng
  1. Trên màn hình xe, chuyển cổng USB sang chế độ Device.
  2. Nối cáp USB từ cổng USB của xe vào máy tính.
  3. Nhấp đúp install.bat, chọn mục cần làm:
       [1] Cài đặt tự động cho xe KIA
           (kiểm tra xe, cài G-Navi Pro, cấp quyền thư mục, tải dữ liệu, mở ứng dụng)
       [2] Cập nhật G-Navi Pro lên xe
       [3] Cập nhật bản đồ & cảnh báo
       [4] Cho phép xe lưu dữ liệu
  4. Lần đầu, màn hình xe hỏi "Cho phép gỡ lỗi USB?" - chọn Luôn cho phép.

Máy tính cần có Internet (file được tải từ GitHub). Windows 10/11, không cần cài thêm gì.

Nếu máy tính không thấy xe: cài driver USB cho xe (Google USB Driver hoặc driver của hãng).

Thư mục
  install.bat / install.ps1   chương trình cài đặt
  platform-tools\             adb.exe, AdbWinApi.dll, AdbWinUsbApi.dll (Android SDK Platform-Tools)

Tham số (kỹ thuật viên, chạy thử) - truyền sau install.bat
  -Mode kia|app|maps|grant    chạy thẳng một mục, không hiện menu
  -Serial <mã thiết bị>       chọn thiết bị khi có nhiều thiết bị nối cùng lúc
  -Dir <thư mục trên xe>      mặc định /storage/GNX/GNaviAlerts (đổi khi chạy thử trên điện thoại)
  -Maps none|all|a,b          chọn gói bản đồ không hỏi (ví dụ viet_nam,bien_dong)
  -NoLaunch                   không mở ứng dụng trên xe khi xong
  -AllowUninstall             tự đồng ý gỡ bản cũ khi xung đột (mặc định luôn hỏi)
  Đặt biến GNAVI_NOPAUSE=1 để cửa sổ không dừng chờ phím khi kết thúc.
