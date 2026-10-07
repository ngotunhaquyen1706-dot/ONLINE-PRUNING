# ONLINE-PRUNING 

Repository này tổng hợp ba hướng thử nghiệm pruning cho **QK attention** với mục tiêu cuối cùng là tìm một phương pháp pruning phù hợp với kiến trúc **systolic array 32×32**.

## 1. Mục tiêu chung

Attention có dạng:

```text
Q, K
 ↓
QKᵀ
 ↓
chia thành các block 32×32
 ↓
xác định block quan trọng
 ↓
KEEP / PRUNE
 ↓
Softmax
 ↓
Attention × V
```

Ý tưởng chính là giảm số lượng block QK cần tính nhưng vẫn giữ chất lượng mô hình gần với Dense baseline.

Một điểm quan trọng là attention sử dụng **causal mask**. Vì vậy các block nằm hoàn toàn ở vùng phía trên đường chéo không chứa giá trị attention hợp lệ và không được đưa vào tập candidate để pruning.

Ba hướng trong repository:

| Hướng | Ý tưởng chính | Mục đích |
|---|---|---|
| **IMPORTANT L1** | Tính QKᵀ trước, sau đó dùng L1 importance của từng block | Xác định ngưỡng `T` và kiểm chứng khả năng pruning |
| **NORM BASE** | Dùng ||Q_block||F × ||K_block||F để dự đoán block quan trọng trước khi tính QKᵀ | Giảm chi phí ranking và tránh tính toàn bộ QKᵀ |
| **NORM BASE INT8** | Quantize Q/K về INT8 rồi dùng norm proxy để ranking | Đưa ý tưởng Norm Proxy gần hơn với triển khai phần cứng/edge |

---

## 2. Hướng 1 — IMPORTANT L1

Hướng đầu tiên dùng chính giá trị QK để đánh giá mức độ quan trọng của từng block.

Với block `B`:

\[
I(B)=\frac{1}{N}\sum_{i,j}|B_{ij}|
\]

Các block được xếp hạng theo `I(B)` và chỉ giữ lại Top-K block.

Kết quả quan trọng:

- Block size: **32×32**
- Sparsity được khảo sát: **50%, 70%, 80%, 90%**
- Dataset: LongBench
- Tasks: `narrativeqa`, `qasper`, `gov_report`
- 15 samples/task → **45 samples/sparsity**
- Dense baseline: **11.8900**
- Ở 90% sparsity, measured sparsity đạt **89.9902%**
- QK average ở 90%: **12.0667**
- Threshold trung bình ở 90%: **12.687973**

Hướng này cho thấy QK block sparsity cao có thể đạt được trong tập thử nghiệm trong khi điểm trung bình vẫn gần Dense baseline.

> Chi tiết kết quả và cách xác định threshold được trình bày trong `IMPORTANT L1/README.md`.

---

## 3. Hướng 2 — NORM BASE

Thay vì tính toàn bộ QKᵀ rồi mới ranking, Norm Base sử dụng một proxy:

\[
P_{ij}=\|Q_i\|_F\|K_j\|_F
\]

Trong đó `Q_i` và `K_j` là các block 32 token.

Quy trình:

```text
Q, K
 ↓
chia block 32×D
 ↓
tính ||Q_i||F và ||K_j||F
 ↓
Pij = ||Q_i||F × ||K_j||F
 ↓
Top-K
 ↓
chỉ tính exact QK cho block được chọn
```

Các norm được tính một lần và có thể được reuse cho nhiều cặp Q/K block.

Điểm quan trọng:

- Không dùng L1(QK)
- Không cần tính full QKᵀ để ranking
- Q/K block norms được vectorize
- Exact QK chỉ được tính cho block được chọn
- Các block được xử lý theo batch để giảm Python-loop overhead

---

## 4. Hướng 3 — NORM BASE INT8

Hướng này tiếp tục ý tưởng Norm Proxy nhưng đưa Q/K sang biểu diễn INT8.

Proxy được sử dụng:

\[
P_{ij}=\|Q8_i\|_F\|K8_j\|_F
\]

Sau khi ranking bằng proxy, chỉ các block được chọn mới thực hiện exact QK.

Notebook hiện có các thí nghiệm:

- Block size: **32×32**
- Sparsity: **50%, 70%, 80%, 90%**
- LongBench tasks:
  - `narrativeqa`
  - `qasper`
  - `gov_report`
- 5 samples/task trong các run INT8 hiện tại
- Dense baseline được reuse: **11.8900**

Các run được chia thành:
- Experiment A: **50% / 70%**
- Experiment B: **80% / 90%**

Hướng này là bước chuyển từ ý tưởng Norm Proxy sang một pipeline phù hợp hơn với mục tiêu **INT8 + hardware acceleration**.

---

## 5. So sánh ba hướng

| Đặc điểm | IMPORTANT L1 | NORM BASE | NORM BASE INT8 |
|---|---:|---:|---:|
| Block | 32×32 | 32×32 | 32×32 |
| Ranking dựa trên | QK block L1 | Q/K norms | INT8 Q/K norms |
| Cần full QKᵀ để ranking | Có | Không | Không |
| Exact QK | Sau ranking | Chỉ block được chọn | Chỉ block được chọn |
| INT8 | Không | Không | Có |
| Mục tiêu chính | Tìm threshold + baseline | Giảm chi phí ranking | Edge/hardware-oriented |

---

## 6. Kết luận hiện tại

Ba hướng thể hiện một quá trình phát triển:

```text
IMPORTANT L1
    ↓
xác định block importance và khả năng đạt sparsity cao
    ↓
NORM BASE
    ↓
dự đoán importance trước khi tính QKᵀ
    ↓
NORM BASE INT8
    ↓
đưa proxy sang dữ liệu INT8
    ↓
hướng tới triển khai trên hardware
```

Hướng **IMPORTANT L1** đóng vai trò reference/baseline về block importance.

Hướng **NORM BASE** là bước quan trọng về mặt thuật toán vì loại bỏ nhu cầu tính full QKᵀ trước khi ranking.

Hướng **NORM BASE INT8** tiếp tục đưa phương pháp về gần mục tiêu triển khai trên accelerator.

## 7. Thư mục

```text
ONLINE-PRUNING/
├── README.md
│
├── IMPORTANT L1/
│   ├── THRESHOLD_COLAB.ipynb
│   └── README.md
│
├── NORM BASE/
│   ├── Llama7B_NORM_BASE_COLAB.ipynb
│   └── README.md
│
└── NORM BASE INT8/
    ├── Llama7B_INT8_NORM_BASE_COLAB.ipynb
    └── README.md
```

## 8. Reproducibility

Các kết quả trong repository là kết quả thực nghiệm trên Colab và LongBench với cấu hình được mô tả trong từng README.

Khi mở rộng thí nghiệm, cần giữ cố định:
- model
- block size
- task
- sample selection
- evaluation pipeline

để việc so sánh giữa các hướng có ý nghĩa.
