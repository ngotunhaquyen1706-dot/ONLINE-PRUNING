# Hướng 2 — NORM BASE

## 1. Mục tiêu

Hướng NORM BASE được xây dựng để giải quyết hạn chế của IMPORTANT L1:

> IMPORTANT L1 phải tính QKᵀ trước rồi mới biết block nào quan trọng.

NORM BASE thử dự đoán block quan trọng **trước khi tính exact QKᵀ**.

---

## 2. Norm Proxy

Với Q block `Qi` và K block `Kj`, proxy được định nghĩa:

\[
P_{ij}=\|Q_i\|_F\|K_j\|_F
\]

Trong đó:

- `Qi`: một Q block gồm 32 token
- `Kj`: một K block gồm 32 token
- `||.||F`: Frobenius norm

---

## 3. Cách hoạt động

Thay vì:

```text
Q,K
 ↓
QKᵀ toàn bộ
 ↓
chia block
 ↓
L1 importance
 ↓
Top-K
```

NORM BASE sử dụng:

```text
Q
 ↓
chia Q thành block 32×D
 ↓
||Q_i||F
          \
           × → Proxy Pij → Top-K
          /
||K_j||F
 ↓
chia K thành block 32×D
 ↓
||K_j||F
```

Sau khi chọn block:

```text
Top-K selected blocks
        ↓
Exact QK chỉ trên các block được chọn
        ↓
causal mask
        ↓
softmax
        ↓
attention × V
```

---

## 4. Điểm quan trọng

NORM BASE:

- **không tính L1(QK)**;
- **không dùng L1 ranking**;
- **không cần full QKᵀ để ranking**;
- Q/K block norms được tính theo cách vectorized;
- các norm được reuse cho nhiều cặp Q/K block;
- exact QK chỉ được tính cho các block được chọn;
- selected QK blocks được xử lý theo batch để giảm overhead.

Đây là thay đổi quan trọng nhất so với IMPORTANT L1.

---

## 5. Vì sao norm có thể dùng làm proxy?

Norm đo magnitude của Q và K.

Với:

\[
P_{ij}=\|Q_i\|_F\|K_j\|_F
\]

một cặp Q/K block có magnitude lớn sẽ nhận proxy score lớn hơn và có khả năng được ưu tiên khi Top-K.

Điểm cần lưu ý:

> Proxy không phải là QKᵀ và không phải giá trị attention thực tế.

Nó chỉ đóng vai trò **ước lượng/ranking trước** để quyết định block nào đáng tính exact QK.

---

## 6. Reuse

Một lợi ích quan trọng là mỗi Q/K block chỉ cần tính norm một lần.

Ví dụ:

```text
||Q0|| ||Q1|| ||Q2|| ...
||K0|| ||K1|| ||K2|| ...
```

Sau đó có thể tạo nhiều proxy score:

```text
Q0 × K0
Q0 × K1
Q0 × K2
Q1 × K0
Q1 × K1
...
```

Các norm được reuse thay vì phải thực hiện phép nhân ma trận đầy đủ cho mọi cặp block.

---

## 7. Experimental setup

Notebook sử dụng:

- Model: Llama-2-7B-Chat
- Block size: 32×32
- Dataset: LongBench
- Tasks:
  - `narrativeqa`
  - `qasper`
  - `gov_report`
- Cùng bộ 45 samples được dùng cho các điều kiện trong experiment chính
- Sparsity: 50%, 70%, 80%, 90%
- Dense baseline: **11.8900**

Notebook được thiết kế để Dense baseline chạy một lần và các experiment Norm Proxy reuse cùng baseline.

---

## 8. Ý nghĩa của kết quả

Hướng NORM BASE chuyển vấn đề từ:

```text
"tính QK trước rồi mới biết nên prune gì"
```

sang:

```text
"ước lượng block trước → chỉ tính QK khi cần"
```

Điều này quan trọng hơn IMPORTANT L1 nếu mục tiêu cuối cùng là accelerator, vì phần cần giảm không chỉ là số block sau pruning mà còn là **chi phí để xác định block nào cần tính**.

---

## 9. Hạn chế hiện tại

NORM BASE vẫn còn một bước exact QK cho các block được chọn.

Ngoài ra, việc ranking proxy cần được kiểm tra với reference QK để xác định:

- ranking có tương quan đủ tốt hay không;
- Top-K overlap có cao không;
- sparsity cao có làm chất lượng giảm không.

Do đó bước tiếp theo là kiểm tra NORM BASE ở dạng **INT8**, đồng thời đo trực tiếp chất lượng của proxy ranking.

---

## 10. Kết luận

NORM BASE là bước chuyển từ **importance-based pruning** sang **predict-before-compute pruning**.

Ý tưởng cốt lõi:

\[
\boxed{P_{ij}=\|Q_i\|_F\|K_j\|_F}
\]

Nếu proxy đủ tốt, có thể bỏ qua phần lớn QKᵀ và chỉ tính exact QK cho các block được chọn.

Đây là nền tảng trực tiếp cho hướng **NORM BASE INT8**.

Nguồn phương pháp: notebook `Llama7B_NORM_BASE_COLAB.ipynb` và tài liệu `T.docx`.
