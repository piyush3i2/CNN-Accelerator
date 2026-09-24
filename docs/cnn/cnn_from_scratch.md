# CNN Reference Sheet

A lookup page. The teaching — with worked examples, intuition and common
mistakes for every term — is in
[day_by_day/01_Day1_CNN_Fundamentals/03_THEORY.md](../../day_by_day/01_Day1_CNN_Fundamentals/03_THEORY.md).

---

## Glossary

| Term | One-line definition | In this design |
|---|---|---|
| **Pixel** | one brightness value | int8 |
| **Channel** | one 2-D slice of a tensor | 1 at the input, 1 (or 2) after conv |
| **Tensor** | multi-dimensional array, shape `C × H × W` | image is 1×8×8 |
| **Kernel / filter** | small grid of learned weights | 3×3 int8 |
| **Convolution** | kernel slid over input; dot product at each position | cross-correlation (no flip), like every DL framework |
| **Feature map** | the output grid of one kernel | 6×6 |
| **Stride** | step size of the slide | 1 |
| **Padding** | zeros added around the border | none ("valid") |
| **Receptive field** | input region one output depends on | conv 3×3, pooled 4×4, FC whole image |
| **Bias** | constant added per output channel / neuron | int32, added at accumulator width |
| **Activation** | non-linear function applied per value | ReLU |
| **ReLU** | `max(x, 0)` | one comparator in `requantize` |
| **Pooling** | downsample by keeping max (or mean) of each window | max, 2×2, stride 2 |
| **Flatten** | reshape a map into a vector | free: pooled values are already contiguous |
| **Fully-connected** | each output = dot product with all inputs + bias | 9 → 4 |
| **Logit** | raw output score per class | int32, not requantised |
| **Inference** | one forward pass, input to logits | 360 MACs |
| **Weight** | fixed learned parameter | 45 bytes + 5 biases |
| **Activation (value)** | data flowing through the network | changes per image |
| **MAC** | multiply-accumulate: `acc += a × b` | one unit, shared |
| **Quantisation** | representing values with fewer bits | int8 × int8 → int32 |
| **Requantisation** | int32 accumulator back to int8 | bias → ReLU → `>>>` → saturate |

---

## Formulas

```
Neuron           y = f( Σ wᵢ·xᵢ + b )
Conv output      out[r][c] = Σ_kr Σ_kc in[r+kr][c+kc] · k[kr][kc]
Output size      out = floor((in + 2·pad − k) / stride) + 1
Max pool 2×2     p[r][c] = max(f[2r][2c], f[2r][2c+1], f[2r+1][2c], f[2r+1][2c+1])
FC               logit[n] = Σ_t x[t] · W[n][t] + b[n]
Row-major addr   addr = row × WIDTH + col
Accumulator      bits ≥ in_bits + wt_bits + ceil(log2(terms))
```

---

## This network

```
 8×8 int8  ──conv 3×3──▶  6×6 int32  ──+b, ReLU, >>s, sat──▶  6×6 int8
           324 MACs
 6×6 int8  ──maxpool 2×2──▶  3×3 int8  ──flatten──▶  9 int8
 9 int8    ──FC 9→4──▶  4 int32 logits                          36 MACs
                                                          total 360 MACs
```

## LeNet-5, for comparison

| Layer | LeNet-5 | This design |
|---|---|---|
| Input | 32×32×1 | 8×8×1 |
| Conv 1 | 6 kernels 5×5 → 6×28×28 | 1 kernel 3×3 → 1×6×6 |
| Pool 1 | 2×2 → 6×14×14 | 2×2 → 1×3×3 |
| Conv 2 | 16 kernels 5×5 → 16×10×10 | — |
| Pool 2 | 2×2 → 16×5×5 | — |
| FC | 120 → 84 → 10 | 9 → 4 |
| Parameters | ~60 thousand | 50 |
| MACs | a few hundred thousand | 360 |

Same *kinds* of layer, same arithmetic, same hardware problems. Different
scale.

---

## In my own words

*(Day 1, Block D2: write one paragraph here — what surprised you today, and how
you would explain a convolution to someone who has never heard of one.)*


Convolution is the process of extracting a particular data from any matrix((which in case inhere is an image) , so image can be either a grayscal (2D array) or colored(3D array).) by multiplying it with the kernel(feature extractor , so called) , when we multiply the each array[][] with sopossed kernel , and give it acculmulated output , it completes the step one of our model.


now asume from 8*8 matrix , and 3*3 kernel we got a 6*6 ouput(feature map - as it contains the extracted feature).
now the second step is applying the ReLU function ie, a non linear activation function to introduce non linearity in our model , relu(x) = max(0, x).

so now we still have 6*6 matrix , which is here feasible by size of 36 memory addres, but for large image it aint , so we come to pooling step , means  reduing the size of output matrix , it can be maxpooling , minpooling, avgpooling , etc.. they are just for the sole purpose of reducing the size of our orignal output , so asuume we have pooling matrix of 2*2 size and strides of 2. So, it would output the 3*3 reduced matrix , by taking out max value from 2*2 pairs of the output

now finally after pooling , we can go agin all these steps , for more dense model , but we keep it here for now.

so after final output we come to flatting option , means , make vector out of the output matrix.


this is our vector or flat layer , now comes the second part the fully connected layer

where each vector is connected with each neurons , and each neurons have specific weinght for each vector , and a bais for all of them , so it means 

for a single neuron we can have weight[len(vector)] as weight matrix , and a same bias for all of them.

the operation is logit of neuron01 =  sum(weight*vector) + bias

and we will get logit for all neuron and then would pick up the logit and neuron with highest number 
