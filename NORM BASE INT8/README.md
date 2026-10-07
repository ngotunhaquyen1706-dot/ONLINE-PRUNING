# Hướng 3 — NORM BASE INT8

## 1. Mục tiêu

NORM BASE INT8 tiếp tục ý tưởng của NORM BASE nhưng đưa Q/K sang biểu diễn **INT8**.

Mục tiêu là kiểm tra xem norm proxy vẫn có thể dùng để ranking block khi Q/K được quantize, từ đó tiến gần hơn đến triển khai trên edge accelerator/hardware.

---

## 2. INT8 Norm Proxy

Proxy được sử dụng:

\[
P_{ij}=\|Q8_i\|_F\|K8_j\|_F
\]

Trong đó:

- `Q8_i`: Q block ở INT8
- `K8_j`: K block ở INT8
- `||.||F`: Frobenius norm

Quy trình:

```text
Q, K
 ↓
RoPE
 ↓
INT8 representation
 ↓
Q8/K8 block norms
 ↓
||Q8_i||F × ||K8_j||F
 ↓
Top-K
 ↓
Exact QK chỉ cho selected blocks
 ↓
causal mask
 ↓
softmax
 ↓
attention × V
```

---

## 3. Khác gì với NORM BASE?

| | NORM BASE | NORM BASE INT8 |
|---|---|---|
| Q/K | floating-point | INT8 representation |
| Proxy | `||Q||F × ||K||F` | `||Q8||F × ||K8||F` |
| L1 QK | Không | Không |
| Full QK để ranking | Không | Không |
| Block | 32×32 | 32×32 |
| Mục tiêu | kiểm chứng thuật toán | hướng tới edge/hardware |

Điểm quan trọng là INT8 không thay đổi ý tưởng ranking chính:

\[
\text{norm}(Q)\times\text{norm}(K)
\]

mà thay đổi representation của Q/K để giảm chi phí và phù hợp hơn với phần cứng.

---

## 4. Implementation

Notebook sử dụng một attention patch riêng cho Norm Proxy.

Các optimization chính:

- Q/K block norms được tính vectorized;
- không tạo full sparse score tensor `[H,Q,K]`;
- không loop Python trên từng selected block;
- selected QK blocks được xử lý bằng batched matrix multiplication;
- causal candidate mask được áp dụng trước khi Top-K;
- decode attention vẫn được xử lý theo cơ chế phù hợp với KV cache.

Proxy:

```text
||Q8_block||F × ||K8_block||F
```

Exact QK:

```text
chỉ tính cho selected blocks
```

---

## 5. Experimental setup

Các run INT8 hiện tại sử dụng:

- Model: Llama-2-7B-Chat
- Block size: **32×32**
- Dataset: LongBench
- Tasks:
  - `narrativeqa`
  - `qasper`
  - `gov_report`
- **5 samples/task**
- Dense baseline được reuse:
  - Average score = **11.8900**
  - `narrativeqa = 0.42`
  - `qasper = 1.08`
  - `gov_report = 34.17`

Các mức sparsity được thiết kế:

```text
50%
70%
80%
90%
```

Notebook hiện chia thành:

```text
Experiment A
    50%
    70%

Experiment B
    80%
    90%
```

Experiment B reuse Dense baseline và không chạy lại Dense.

---

## 6. Kết quả hiện có

Các notebook đã triển khai đầy đủ pipeline INT8 Norm Proxy cho các mức sparsity trên.

Kết quả được lưu theo từng experiment dưới dạng JSON, ví dụ:

```text
int8_norm_proxy_dense_50_70_5samples.json
int8_norm_proxy_80_90_5samples.json
```

Các thống kê được thu thập gồm:

- target sparsity;
- measured sparsity;
- candidate blocks;
- kept blocks;
- average threshold;
- average LongBench score;
- score difference so với Dense;
- điểm từng task.

### Dense reference

```text
Average = 11.8900

narrativeqa = 0.42
qasper      = 1.08
gov_report  = 34.17
```

> README này không tự điền các giá trị LongBench INT8 chưa được lưu trong tài liệu nguồn hiện có. Khi commit JSON result cuối cùng vào repository, có thể bổ sung bảng số liệu trực tiếp từ các file JSON để tránh ghi sai kết quả.

---

## 7. Calibration / Ranking validation

Một bước quan trọng của hướng INT8 là kiểm tra xem ranking bằng:

\[
\|Q8_i\|_F\|K8_j\|_F
\]

có gần với ranking reference hay không.

Các metric phù hợp gồm:

- **Spearman rank correlation**
- **Top-K Jaccard overlap**
- **FP-selection recall**
- **INT8-selection precision**

Ý nghĩa:

```text
Spearman cao
    ↓
proxy giữ được thứ tự importance

Jaccard cao
    ↓
Top-K của INT8 gần Top-K reference

Recall cao
    ↓
INT8 ít bỏ sót các block reference quan trọng

Precision cao
    ↓
INT8 ít chọn nhầm block
```

Calibration nên dùng số sample nhỏ hơn quality experiment để giảm runtime, nhưng vẫn giữ đại diện các task.

---

## 8. Ý nghĩa đối với hardware

Đây là hướng gần nhất với mục tiêu accelerator.

Nếu INT8 Norm Proxy có ranking đủ tốt:

```text
Q/K INT8
   ↓
cheap norm calculation
   ↓
block selection
   ↓
only selected QK
   ↓
32×32 systolic array
```

sẽ phù hợp hơn với kiến trúc systolic 32×32 vì các block được chọn có cùng kích thước 32×32.

Đặc biệt, cách này tránh ý tưởng gộp nhiều block nhỏ thành một block lớn không phù hợp với dataflow coupled của systolic array.

---

## 9. Những điểm cần kiểm tra tiếp

Trước khi kết luận INT8 Norm Proxy là phương pháp cuối cùng, cần kiểm tra:

1. Ranking correlation với FP/reference.
2. Top-K overlap ở 50/70/80/90%.
3. LongBench quality degradation.
4. Chi phí tính norm.
5. Chi phí Top-K selection.
6. Utilization của systolic array khi chỉ còn selected blocks.
7. Memory movement và locality.
8. Overhead do block sparsity không đều.

Đặc biệt cần phân biệt:

```text
Algorithmic sparsity
        ≠
Hardware speedup
```

90% block sparsity không tự động có nghĩa là hardware nhanh hơn 10×. Cần tính thêm scheduling, data movement, padding và PE utilization.

---

## 10. Kết luận

NORM BASE INT8 là bước nối giữa:

```text
NORM BASE
   ↓
cheap proxy ranking
   ↓
INT8 representation
   ↓
sparse QK computation
   ↓
32×32 systolic hardware
```

Mục tiêu cuối cùng không chỉ là đạt sparsity cao, mà là chứng minh rằng **INT8 proxy có thể chọn đúng các block quan trọng với chi phí đủ thấp để phần pruning thực sự có lợi trên hardware**.

Nguồn implementation: `Llama7B_INT8_NORM_BASE_COLAB.ipynb`.
