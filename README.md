# ONLINE-PRUNING

**Nghiên cứu tập trung vào hướng loại bỏ block attention trước phép nhân $QK^T$ (Pre-QKᵀ Block Pruning) cho suy luận mô hình ngôn ngữ lớn.**

Repository tập hợp các thí nghiệm **Important L1** và **Norm-based Proxy** trên Llama 7B, cùng phần khảo sát thuật toán và kiểm chứng RTL **Norm Proxy trên Qwen2.5-0.5B**. Mục tiêu lâu dài là tích hợp cơ chế lựa chọn block vào bộ tăng tốc **GEMM systolic array 32×32** trên FPGA, giúp giảm các phép tính attention không cần thiết trong giai đoạn **prefill**.

> **Trạng thái:** Repository hiện tập trung vào thực nghiệm thuật toán, xuất dữ liệu tham chiếu và mô phỏng/kiểm chứng RTL. Việc tích hợp hoàn chỉnh với đường tính toán GEMM, chạy end-to-end trên KV260 và đo speedup thực tế là các bước triển khai/đánh giá tiếp theo, không được suy ra từ kết quả RTL PASS.

## 1. Bài toán nghiên cứu

Trong self-attention, ma trận điểm $S=QK^T$ có số phần tử tăng theo bình phương độ dài chuỗi. Tuy nhiên, không phải mọi vùng trong ma trận attention đều quan trọng như nhau. Nếu dự đoán được những block ít quan trọng **trước khi** thực hiện $QK^T$, bộ tăng tốc có thể bỏ qua các block đó thay vì tính toàn bộ ma trận.

Hai câu hỏi chính:

1. Có thể xác định block attention **32×32** cần KEEP/PRUNE trước phép nhân $QK^T$ mà vẫn duy trì chất lượng đầu ra của LLM không?
2. Khi triển khai trên FPGA, lợi ích từ số phép tính bị loại bỏ có lớn hơn chi phí tính proxy, lưu trữ, lập lịch và truy cập bộ nhớ không?

## 2. Các hướng thí nghiệm

| Thư mục | Mô hình | Vai trò |
| --- | --- | --- |
| [`IMPORTANT_L1_Llama7B/`](IMPORTANT_L1_Llama7B/) | Llama 7B | Đánh giá độ quan trọng của block từ điểm attention **sau khi** tính $QK^T$; sử dụng làm mốc tham chiếu (*oracle*). |
| [`NORM_BASE_Llama7B/`](NORM_BASE_Llama7B/) | Llama 7B | Khảo sát **Norm-based Proxy** để dự đoán block quan trọng **trước** $QK^T$. |
| [`NORM_BASE_INT8_Llama7B/`](NORM_BASE_INT8_Llama7B/) | Llama 7B | Khảo sát Norm-based Proxy khi lượng tử hóa Q/K sang **INT8**. |
| [`NORM_PROXY_Qwen2.5-0.5B/`](NORM_PROXY_Qwen2.5-0.5B/) | Qwen2.5-0.5B-Instruct | Chạy LongBench, khảo sát ngưỡng **T**, xuất golden data và kiểm chứng các module RTL trên Vivado. |

**Important L1** đánh giá block dựa trên kết quả $QK^T$, nên thích hợp làm chuẩn so sánh nhưng không tự giảm chi phí tính $QK^T$. **Norm-based Proxy** sử dụng Q/K trước GEMM nhằm đưa ra quyết định sớm hơn.

## 3. Ý tưởng Norm-based Proxy

Đối với từng cặp block $(Q_i,K_j)$, phép tính tham chiếu trong nhánh Qwen INT8 là:

$$
N_{Q_i}=\sum_{x\in Q_i}x^2,\qquad
N_{K_j}=\sum_{x\in K_j}x^2
$$

$$
P_{ij}=N_{Q_i}\times N_{K_j}
$$

- **Causal mask:** Không xét những block hoàn toàn nằm ở vùng tương lai ($j>i$).
- **Threshold $T$:** So sánh $P_{ij}$ với $T$ để quyết định **KEEP** (1) hoặc **PRUNE** (0).
- **Lập lịch:** Các cặp KEEP được chuyển thành job $(i,j)$ để bộ tính GEMM xử lý; các cặp PRUNE được bỏ qua.

> Trong nhánh RTL Qwen, proxy dùng **tích hai squared norm (số nguyên)**. Đây là bình phương của tích hai Frobenius norm trong số học lý tưởng; phải dùng đúng định nghĩa/miền giá trị của $T$ khi đối chiếu dữ liệu Python và RTL. Việc lựa chọn $T$ được làm trong phần mềm/Colab; `Norm_Base_Top` hiện **nhận** `threshold_T` từ bên ngoài, không tự tìm T.

## 4. Hai nhánh đánh giá trên Qwen

### A. Phần mềm: Colab / LongBench

- Model: **Qwen2.5-0.5B-Instruct**, nguồn trọng số **GGUF Q4_K_M**, nạp vào Transformers để thực hiện thí nghiệm.
- Lấy Q/K activation sau RoPE; lượng tử hóa Q/K thành INT8 để tính proxy.
- So sánh **Dense** với các mức sparsity mục tiêu **50%, 70%, 80%, 90%**.
- Tổng hợp ngưỡng $T$, sparsity thực tế, số lượng KEEP/PRUNE và điểm LongBench trên các tác vụ `narrativeqa`, `qasper`, `gov_report`.

**Câu hỏi cần trả lời:** Mức pruning nào cho phép giảm số block cần tính mà vẫn giữ chất lượng câu trả lời ở mức chấp nhận được?

### B. Phần cứng: Vivado / RTL verification

- Đưa Q/K INT8, block ID và ngưỡng T từ Colab vào testbench.
- So sánh norm 32-bit, proxy 64-bit, quyết định KEEP/PRUNE và danh sách job với **golden data** của Python.
- Kiểm tra `Norm_Engine`, `Norm_RAM`, `Causal_Block_Mask`, `Proxy_Engine`, `Threshold_Comparator`, `Block_FIFO`, `Block_Scheduler` thông qua các mức testbench khác nhau.

**Câu hỏi cần trả lời:** RTL có thực hiện đúng phép tính và quyết định của thuật toán Python, đồng thời lập lịch đúng cặp block hay không?

## 5. Cấu trúc repository

```text
ONLINE-PRUNING/
├── IMPORTANT_L1_Llama7B/
├── NORM_BASE_Llama7B/
├── NORM_BASE_INT8_Llama7B/
├── NORM_PROXY_Qwen2.5-0.5B/
│   ├── GOLDEN_MODEL/         # Notebook và đầu ra Colab (nếu đã đưa lên Git)
│   ├── RTL/                  # Các module Norm Proxy
│   ├── TB/                   # Testbench Vivado
│   ├── verification/         # Script và báo cáo kiểm chứng
│   ├── fig/                  # Hình/tài liệu minh họa
│   ├── NORM_PROXY.srcs/      # Nguồn được Vivado quản lý
│   ├── NORM_PROXY.xpr        # Project Vivado
│   └── README.md             # Hướng dẫn chi tiết nhánh Qwen
└── README.md
```

*Nhánh Qwen có thể còn các thư mục hỗ trợ như `mem/`. Các cache và file mô phỏng do Vivado tự tạo không phải source chính. `GOLDEN_MODEL/output/` có thể chỉ được lưu ở Drive/máy cục bộ nếu dung lượng quá lớn.*

## 6. Bắt đầu từ đâu?

- **Muốn hiểu các phương pháp pruning:** xem lần lượt `IMPORTANT_L1_Llama7B`, `NORM_BASE_Llama7B` và `NORM_BASE_INT8_Llama7B`.
- **Muốn khảo sát T và chất lượng Qwen:** xem notebook trong `NORM_PROXY_Qwen2.5-0.5B/GOLDEN_MODEL/`.
- **Muốn kiểm chứng RTL:** xem `RTL/`, `TB/`, `verification/` và dữ liệu `GOLDEN_MODEL/output/vivado_testdata/` (nếu có).
- **Hướng dẫn chi tiết nhánh Qwen:** [NORM_PROXY_Qwen2.5-0.5B/README.md](NORM_PROXY_Qwen2.5-0.5B/README.md).

## 7. Phạm vi và cách diễn giải kết quả

- **Điểm LongBench và sparsity** phản ánh chất lượng của phương pháp trên workload đã chọn; không tự suy ra tốc độ FPGA.
- **RTL PASS** xác nhận các phép tính/handshake được kiểm thử khớp với golden data; không đồng nghĩa với hệ thống GEMM đã được tích hợp end-to-end.
- Phần **Buffer Feeder theo block ID, cộng dồn chiều K, ghi kết quả đúng vị trí attention và đo trên KV260** cần được kiểm chứng riêng khi tích hợp.

## 8. Tài liệu tham khảo

- [Qwen2.5-0.5B-Instruct — Hugging Face](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct)
- [LongBench](https://github.com/THUDM/LongBench)
- [GEMM_32x32_KV260 — thiết kế tăng tốc GEMM tham chiếu](https://github.com/VinhPT-Lab/GEMM_32x32_KV260)
- [llama.cpp](https://github.com/ggml-org/llama.cpp)

---

**Tóm tắt:** Repository nghiên cứu cách **dự đoán sớm block attention cần tính** và chuẩn bị cho việc tích hợp cơ chế KEEP/PRUNE vào systolic array GEMM 32×32 trên FPGA.
