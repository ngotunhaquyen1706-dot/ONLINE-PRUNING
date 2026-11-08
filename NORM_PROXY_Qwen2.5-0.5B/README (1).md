# NORM_PROXY — Qwen2.5-0.5B

**Khảo sát ngưỡng T bằng Qwen2.5-0.5B-Instruct, đánh giá sparse attention trên LongBench và kiểm chứng RTL Norm-based Proxy bằng Vivado 2022.2.**

Thư mục này là nhánh triển khai **Qwen** của repository [ONLINE-PRUNING](../README.md). Hai phần chính là **golden model (Colab/Python)** và **RTL verification (Vivado/SystemVerilog)**. Bộ kiểm chứng hiện tập trung vào khối `Norm_Base_Top`; **chưa mặc định có kết nối hoạt động đầy đủ với GEMM/systolic array cũ**.

## 1. Mục tiêu

1. Dùng Q/K activation thực tế để tính **norm → proxy → ngưỡng T** và quyết định **KEEP/PRUNE** trên các block attention.
2. So sánh chất lượng **Dense** và sparse attention ở **50%, 70%, 80%, 90%** bằng một tập con **LongBench**.
3. Xuất Q/K INT8 và kết quả chuẩn (*golden data*) cho testbench RTL.
4. Kiểm chứng `Norm_Base_Top` tính đúng norm, proxy, quyết định và thứ tự job trước khi tích hợp với GEMM 32×32.

## 2. Cấu trúc thư mục và vai trò

```text
NORM_PROXY_Qwen2.5-0.5B/
├── GOLDEN_MODEL/
│   ├── *.ipynb                    # Notebook Colab của thí nghiệm Qwen
│   └── output/                    # Kết quả tải từ Drive (nếu được đưa vào Git)
│       ├── results/               # Thống kê T, LongBench, sparsity
│       ├── predictions/           # Đầu ra sinh văn bản theo tác vụ
│       └── vivado_testdata/       # Dữ liệu HEX/metadata dùng cho Vivado
├── RTL/                           # Source SystemVerilog của Norm Proxy
├── TB/                            # Testbench module và testbench tích hợp
├── verification/                  # Script, CSV, log/báo cáo kiểm chứng
├── fig/                           # Sơ đồ khối, dataflow, control flow, tài liệu/hình
├── NORM_PROXY.srcs/               # File source do project Vivado quản lý
├── NORM_PROXY.xpr                 # File project Vivado
└── README.md
```

**Ghi chú về Git:** `output/` có thể không hiện đầy đủ trên GitHub nếu được giữ riêng vì kích thước. Trong trường hợp đó, tải dữ liệu Colab từ Drive về và đặt đúng cấu trúc trên. `RTL/` và `NORM_PROXY.srcs/` có thể chứa bản sao cùng tên; khi sửa code, phải kiểm tra **Vivado Sources** đang dùng file nào.

### Các thư mục quan trọng

| Thư mục | Chứa gì? | Dùng khi nào? |
| --- | --- | --- |
| **`GOLDEN_MODEL/`** | Notebook Qwen (GGUF Q4_K_M), mã tính threshold, xuất dữ liệu và đánh giá LongBench | Thí nghiệm thuật toán trên Colab |
| **`GOLDEN_MODEL/output/results/`** | Tổng hợp ngưỡng T, thống kê sparse và điểm LongBench | Viết phần kết quả phần mềm |
| **`GOLDEN_MODEL/output/vivado_testdata/`** | Q/K INT8, golden norm/proxy/T/mask và metadata theo test case | Kiểm chứng RTL bằng `$readmemh` |
| **`RTL/`** | `Norm_Base_Top` và các module con | Thiết kế phần cứng |
| **`TB/`** | Testbench chức năng, testbench GUI với Qwen và golden data | Chạy Behavioral Simulation |
| **`verification/`** | Kịch bản kiểm tra và báo cáo PASS/FAIL/CSV | Tổng hợp kiểm chứng |
| **`fig/`** | Sơ đồ kiến trúc, dataflow/control flow và hình tài liệu | Giải thích thiết kế |
| **`NORM_PROXY.srcs/`, `NORM_PROXY.xpr`** | Project Vivado và source references | Mở/biên dịch project |

## 3. Luồng xử lý thuật toán

```text
Qwen2.5-0.5B-Instruct Q4_K_M (Colab)
              |
      Q/K sau RoPE
              |
       Quantize INT8
              |
     Chia block theo token
              |
        Norm Q/K (32 bit)
              |
     Proxy P_ij (64 bit)
              |
      Causal mask + T
         /         \
    KEEP=1       PRUNE=0
       |            |
   Xuất job      Bỏ block
       |
   [GEMM 32x32: đường tích hợp dự kiến]
```

Với Qwen2.5-0.5B: **24 layers**, **14 query heads** và **2 KV heads (GQA)**; kích thước head là **64**. Nếu một đoạn có 2048 token, mỗi Q/K head có kích thước $2048\times64$. Chia thành 64 block theo chiều token (mỗi block 32 token) tạo thành tối đa **2.080 cặp block hợp lệ** dưới causal mask (64×65/2).

Một block $Q_i$ và $K_j$ có kích thước $32\times64$, còn block kết quả $Q_iK_j^T$ là $32\times32$. Cần phân biệt: **block attention 32×32** không có nghĩa là toàn bộ ma trận Q/K chỉ gồm 32×32 phần tử.

### Định nghĩa số học của nhánh RTL

$$
N_{Q_i}=\sum_{x\in Q_i}x^2,\qquad N_{K_j}=\sum_{x\in K_j}x^2
$$

$$
P_{ij}=N_{Q_i}\cdot N_{K_j},\qquad
\mathrm{KEEP}_{ij}=(P_{ij}\ge T_{ij})
$$

- `N_Q`, `N_K`: **32-bit unsigned** (squared norm từ các phần tử Q/K INT8 signed).
- `P_ij`, `T_ij`: **64-bit unsigned**.
- `q_block_id`, `k_block_id`: **8-bit** mỗi ID.
- Quy tắc causal: nếu $j>i$, không có job GEMM cho cặp này.
- Trong thí nghiệm v4, phần mềm **bảo vệ block đường chéo**; testbench có thể dùng `threshold_inputs_XX.hex` với ngưỡng **0 ở cặp đường chéo** và ngưỡng T tương ứng ở cặp khác. Đây là quy tắc **chuẩn bị input**, không phải một bộ tìm ngưỡng T nằm bên trong RTL.

### Hai nhánh của notebook Colab

**Nhánh LongBench:** Chạy **Dense**, **50%**, **70%**, **80%**, **90%**; lưu score, T, sparsity thực tế và số candidate/KEEP/PRUNE. Mục đích là đánh giá tác động của quyết định pruning đến chất lượng đầu ra.

**Nhánh Vivado:** Xuất Q/K INT8 và golden values của Python. Mục đích là xác nhận RTL có tính và quyết định **giống tham chiếu** hay không.

> GGUF **Q4_K_M** mô tả định dạng trọng số model đầu vào. Đối với phép dự đoán norm/proxy, **Q/K activation** được lượng tử hóa **INT8** riêng; không nên gọi đây là phép nhân trực tiếp trên trọng số Q4 trong RTL.

## 4. File output quan trọng từ Colab

### 4.1. Kết quả thuật toán / benchmark

| File (trong `GOLDEN_MODEL/output/`) | Ý nghĩa |
| --- | --- |
| `results/threshold_summary.csv` | Thống kê T theo các mức sparsity (ví dụ mean/median/min/max) |
| `results/threshold_trace_50.jsonl` ... `_90.jsonl` | Giá trị T theo từng sample/layer/head và từng mức pruning |
| `results/sparsity_summary.csv` | Số block candidate/KEEP/PRUNE và sparsity thực tế |
| `results/longbench_scores.csv` | Điểm benchmark Dense và các cấu hình sparse |
| `predictions/` | Các câu trả lời của mô hình để phục vụ đánh giá/chấm điểm |

Tên file thực tế có thể phụ thuộc phiên bản notebook và trạng thái run; kiểm tra file hiện có trong `output/` trước khi trích số liệu vào báo cáo.

### 4.2. Golden data cho Vivado

Thông thường, mỗi test case dưới `GOLDEN_MODEL/output/vivado_testdata/` chứa:

| File | Dùng làm gì? |
| --- | --- |
| `q_int8.hex`, `k_int8.hex` | Dữ liệu Q/K INT8, packing **256-bit/beat** = 32 phần tử INT8 |
| `q_norm_sq.hex`, `k_norm_sq.hex` | Norm 32-bit chuẩn của Python |
| `pairs.hex` | Danh sách cặp `(q_id, k_id)` cần kiểm chứng |
| `expected_proxy.hex` | Proxy 64-bit chuẩn |
| `threshold_50.hex` ... `threshold_90.hex` | Ngưỡng T cho từng mức |
| `threshold_inputs_50.hex` ... `threshold_inputs_90.hex` | Ngưỡng thực sự cấp đến Comparator cho từng cặp |
| `expected_mask_50.hex` ... `expected_mask_90.hex` | Bit KEEP=1 / PRUNE=0 dự kiến cho từng cặp |
| `metadata.json` | Sample, layer, head, số block/beat, scale và cấu hình test |
| `manifest.json` | Danh mục các test case (ở cấp thư mục dữ liệu) |

Trong cấu hình lấy mẫu cho kiểm chứng RTL, notebook v4 lựa chọn **các layer 0, 12, 23** và **query head 0, 7** từ các mẫu LongBench đã chọn. Hãy dùng `manifest.json`/`metadata.json` làm nguồn xác nhận các case thực sự được xuất trong lần chạy cụ thể.

## 5. Các module RTL và tín hiệu quan trọng

### `Norm_Base_Top` (top-level)

**Input chính:**

- `clk`, `rst`
- `q_start`, `k_start`, `q_valid`, `k_valid`, `q_last`, `k_last`
- `q_data[255:0]`, `k_data[255:0]` (signed, 256-bit)
- `q_block_id[7:0]`, `k_block_id[7:0]`
- `pair_valid`, `pair_q_id[7:0]`, `pair_k_id[7:0]`
- `threshold_T[63:0]`, `job_ready`

**Output chính:**

- `q_busy`, `k_busy`, `q_done`, `k_done`, `pair_ready`, `pair_error`
- `decision_valid`, `decision_keep`
- `decision_q_id[7:0]`, `decision_k_id[7:0]`
- `decision_q_norm[31:0]`, `decision_k_norm[31:0]`
- `decision_score[63:0]`, `decision_threshold[63:0]`
- `job_valid`, `job_q_id[7:0]`, `job_k_id[7:0]`

Các độ rộng trên dựa vào tham số mặc định `ID_W=8`, `NORM_W=32` của `Norm_Base_Top`.

### Chức năng các module con

| Module | Chức năng | Output cần quan sát |
| --- | --- | --- |
| `Norm_Engine` ×2 | Tính squared norm Q/K từ stream INT8 | `norm_sq[31:0]`, `norm_valid`, `norm_block_id` |
| `Norm_RAM` ×2 | Lưu norm theo block ID, đọc đồng bộ | `rd_norm[31:0]`, `rd_valid`, `rd_present` |
| `Causal_Block_Mask` | Chặn cặp tương lai $k\_id>q\_id$ | `out_valid`, `causal_prune`, output ID |
| `Proxy_Engine` | Nhân hai norm để ra proxy | `proxy_score[63:0]`, `out_valid`, output ID |
| `Threshold_Comparator` | So sánh `proxy_score >= threshold_T` | `keep`, `out_valid`, output ID |
| `Block_FIFO` | Lưu các cặp KEEP (mặc định depth=8) | `out_valid`, `out_q_id`, `out_k_id`, `count` |
| `Block_Scheduler` | Chuyển job theo handshake `job_valid/job_ready` | `job_valid`, `job_q_id`, `job_k_id` |

FSM thực tế trong `Norm_Base_Top`: `IDLE → READ_NORMS → WAIT_PROXY → WAIT_COMPARE → ENQUEUE` (nhánh PRUNE quay lại IDLE, không enqueue).

## 6. Bốn testbench chính và câu hỏi kiểm chứng

| Testbench | Dữ liệu | Trả lời câu hỏi nào? |
| --- | --- | --- |
| `tb_proxy_comparator_GUI_v4.sv` | Bộ deterministic 64 token | Proxy + Comparator có đưa ra đúng KEEP/PRUNE ở 4 ngưỡng không? |
| `tb_norm_proxy_GUI_v4.sv` | Bộ deterministic 64 token | Toàn bộ `Norm_Base_Top` có phối hợp đúng từ norm đến FIFO/Scheduler không? |
| `tb_Qwen_Real2048_Comparator_GUI.sv` | Qwen thực tế (tối đa 2048 token) | Proxy và quyết định T có đúng trên Qwen với 50/70/80/90% không? |
| `tb_Qwen_Real2048_AllT_GUI.sv` | Qwen thực tế (tối đa 2048 token) | Toàn bộ Norm/Proxy/KEEP/Scheduler có khớp golden data trên 4 mức không? |

**Kết quả đã ghi nhận:** test deterministic 64 token đã PASS ở các phép so sánh đã chạy; vì chỉ có 3 cặp causal hợp lệ và 2 cặp đường chéo bắt buộc KEEP, sparsity thực tế khi đó chỉ là **33,33%**, dù mức yêu cầu là 50–90%. Điều này **không thể** dùng để kết luận 4 mức sparsity đã đạt trên Qwen thực tế.

**Lưu ý bản V5:** đã từng phát hiện lỗi xử lý signed INT8 trong phép tự kiểm tra norm của testbench `tb_Qwen_Real2048_AllT_GUI`. Cần sử dụng bản testbench đã sửa và xác nhận PASS với dữ liệu Qwen thực trước khi ghi kết quả vào báo cáo.

## 7. Chạy lại bằng Google Colab

1. Mở notebook v4 trong `GOLDEN_MODEL/` bằng **Google Colab**; chọn **T4 GPU**.
2. Kết nối Google Drive khi được yêu cầu và chạy các cell theo thứ tự.
3. Đọc kết quả LongBench, threshold và sparsity trong `results/`.
4. Dùng `vivado_testdata/` chứa golden HEX để đưa sang máy Windows.

Đường dẫn kết quả của notebook v4 trên Drive được dùng trong lần chạy trước:

```text
MyDrive/QWEN_NORM_PROXY_Q4KM_RUN_V4_T_RTL/
```

Tệp GGUF lớn, Hugging Face cache và các file môi trường không bắt buộc phải đưa vào GitHub.

## 8. Chạy kiểm chứng RTL bằng Vivado GUI

1. Mở `NORM_PROXY.xpr` trong **Vivado 2022.2**.
2. Xác nhận đúng source RTL trong `Design Sources` và testbench trong `Simulation Sources`.
3. Chuẩn bị dữ liệu tại `GOLDEN_MODEL/output/vivado_testdata/` (hoặc một đường dẫn khác).
4. Mở file testbench và sửa hằng đường dẫn `CASE_DIR`/`DATA_DIR` để trỏ đến **case thực có `metadata.json` và HEX**; không dùng lại đường dẫn cũ nếu đã chuyển thư mục.
5. Chuột phải testbench cần chạy → **Set as Top** → **Run Behavioral Simulation** → **Run All**.
6. Kiểm tra `RTL_PASS`/`FAIL` và các CSV/log trong `verification/` hoặc đường dẫn report do testbench thiết lập.

**Đối chiếu đúng thời điểm:** chỉ so sánh `decision_q_norm`, `decision_k_norm`, `decision_score`, `decision_keep`, `decision_*_id` khi `decision_valid=1`; với job chỉ đối chiếu khi `job_valid && job_ready`.

## 9. Phạm vi đã làm và phần còn cần tích hợp

**Phần đã thiết kế/khảo sát:**

- Notebook tính T, đánh giá LongBench và tạo golden data.
- RTL `Norm_Base_Top` cùng khối norm, RAM, causal, proxy, comparator, FIFO/scheduler.
- Các testbench nhỏ và testbench sử dụng activation Qwen.

**Phần tích hợp cần thực hiện hoặc xác nhận riêng:**

- Nối `job_q_id/job_k_id` đến **Buffer Feeder** để nạp đúng block Q/K cho GEMM.
- Tích lũy kết quả khi $d_{head}=64$ (hai lượt chiều K=32 nếu theo cách chia tile đó).
- Giữ metadata `(i,j)` đồng bộ tới kết quả và bố trí **Sparse Result Writer/Result Placer** về đúng vị trí attention (module đề xuất, không thuộc `Norm_Base_Top` hiện tại).
- Giữ hành vi causal/softmax đúng với các block PRUNE.
- Đánh giá utilization, frequency, memory traffic và end-to-end speedup thực tế trên **Kria KV260**.

> **Không nhầm lẫn:** Kết quả testbench RTL PASS xác nhận chức năng đã kiểm thử; không đồng nghĩa với việc nhánh GEMM/llama.cpp đã tích hợp hoàn chỉnh hay đã đo được speedup FPGA.

## 10. Tài liệu tham khảo

- [Repository gốc ONLINE-PRUNING](../README.md)
- [Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct)
- [LongBench](https://github.com/THUDM/LongBench)
- [GEMM_32x32_KV260](https://github.com/VinhPT-Lab/GEMM_32x32_KV260)

---

**Tóm lại:** `GOLDEN_MODEL` trả lời **ngưỡng nào, block nào và chất lượng ra sao**; `RTL` + `TB` trả lời **phần cứng có tính đúng và lập lịch đúng không**. Bước sau đó là nối job KEEP vào GEMM và đo hiệu quả FPGA thực tế.
