# Hướng 1 — IMPORTANT L1 / Tìm ngưỡng T

## 1. Mục tiêu

Hướng này kiểm tra xem **QK block importance** có thể được sử dụng để pruning hay không, đồng thời xác định ngưỡng `T` tương ứng với từng mức sparsity.

Block size được cố định:

```text
32 × 32
```

Một block 32×32 có:

```text
N = 32 × 32 = 1024 phần tử
```

---

## 2. L1 Block Importance

Với một block `B`, importance được tính:

<img width="261" height="102" alt="image" src="https://github.com/user-attachments/assets/9135bb0d-bc8a-4348-b116-5d76fb41fb05" />

Tức là:
1. lấy trị tuyệt đối của các QK score hợp lệ trong block;
2. cộng lại;
3. chia cho số phần tử hợp lệ.

Ví dụ:

```text
B = [ 2  -4
      1   3 ]
```

thì:

\[
I(B)=\frac{|2|+|-4|+|1|+|3|}{4}
=\frac{2+4+1+3}{4}
=2.5
\]

Sau khi tính importance cho toàn bộ candidate blocks:

```text
QKᵀ
 ↓
32×32 blocks
 ↓
L1 importance
 ↓
xếp hạng
 ↓
Top-K
 ↓
KEEP / PRUNE
```

---

## 3. Xử lý causal mask

Attention dùng causal mask nên vùng phía trên đường chéo không chứa thông tin attention hợp lệ.

Do đó:

- Block nằm hoàn toàn trong vùng bị mask → **không phải candidate**
- Block nằm một phần trong vùng hợp lệ → chỉ tính các giá trị hợp lệ
- Các giá trị `-∞` do causal mask → **bỏ qua khi tính L1**

Ví dụ:

```text
B11 = [ 8  -∞
        1   7 ]
```

chỉ dùng:

```text
8, 1, 7
```

để tính importance.

### Target sparsity

Sparsity chỉ được áp dụng trên **candidate blocks**, không áp dụng lên các block đã bị causal mask.

Ví dụ:

```text
Total blocks     = 16
Candidate blocks = 10
Invalid blocks   = 6
```

Nếu target sparsity = 90%:

\[
K=10(1-0.9)=1
\]

→ giữ 1 candidate block quan trọng nhất  
→ prune 9 candidate blocks.

---

## 4. Xác định threshold T

Threshold được lấy từ **importance của block cuối cùng được giữ lại**:

\[
I(B)\ge T \Rightarrow KEEP
\]

\[
I(B)<T \Rightarrow PRUNE
\]

Vì vậy `T` phụ thuộc vào target sparsity và phân bố importance của các candidate blocks.

---

## 5. Experimental setup

Thực nghiệm sử dụng:

- Model: Llama-2-7B-Chat
- Block size: 32×32
- Dataset: LongBench
- Tasks:
  - `narrativeqa`
  - `qasper`
  - `gov_report`
- 15 samples/task
- 45 samples/sparsity
- Sparsity: 50%, 70%, 80%, 90%

Dense baseline:

```text
11.8900
```

---

## 6. Kết quả

| Sparsity | Measured | QK Avg | Score Difference* | Threshold |
|---:|---:|---:|---:|---:|
| 50% | 49.9947% | 12.1300 | +0.2400 | 1.816662 |
| 70% | 69.9951% | 12.0700 | +0.1800 | 5.096291 |
| 80% | 80.0049% | 12.0633 | +0.1733 | 8.629588 |
| 90% | 89.9902% | 12.0667 | +0.1767 | 12.687973 |

\* `Score Difference` ở bảng này được trình bày theo `QK Avg - Dense`. Vì vậy giá trị dương nghĩa là điểm QK trong tập thử nghiệm cao hơn Dense; **không nên diễn giải thành pruning làm model tốt hơn**.

Ở 90% sparsity:

```text
Measured sparsity ≈ 89.99%
QK average        ≈ 12.0667
Dense             = 11.8900
Threshold         ≈ 12.687973
```

Kết quả cho thấy trong tập thử nghiệm, có thể tăng QK block sparsity lên khoảng 90% trong khi điểm trung bình vẫn gần Dense baseline.

---

## 7. Per-task ở 90%

```text
Dense:
narrativeqa = 0.42
qasper      = 1.08
gov_report  = 34.17

QK 90%:
narrativeqa = 0.41
qasper      = 1.05
gov_report  = 34.74
```

---

## 8. Ý nghĩa đối với hardware

Hướng L1 cho một reference rõ ràng:

```text
Q, K
 ↓
QK block 32×32
 ↓
L1 importance
 ↓
so với T
 ↓
KEEP / PRUNE
```

Tuy nhiên, cách này vẫn tính QK trước rồi mới biết block nào quan trọng. Vì vậy nó phù hợp để:

- xác định block importance;
- tìm threshold;
- làm reference cho các proxy rẻ hơn.

Nó chưa giải quyết hoàn toàn vấn đề **chi phí tính QKᵀ trước pruning**.

Đây là động lực chuyển sang **NORM BASE**.

---

## 9. Kết luận

IMPORTANT L1 chứng minh rằng:

> QK block có thể được xếp hạng theo magnitude và pruning ở mức sparsity cao vẫn giữ chất lượng gần Dense trong tập thử nghiệm.

Bước tiếp theo là tìm một cách dự đoán importance **trước khi tính QKᵀ**.

Nguồn cấu hình và kết quả: tài liệu `T.docx` và notebook `THRESHOLD_COLAB.ipynb`.
