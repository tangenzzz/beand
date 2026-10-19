# Models

## u2netp_fp16.tflite

U²-Net, the small variant (u2netp), used on Android to cut gear photos out
of their background (My Coffee Desk). On iOS the system's Vision framework
does this instead.

- Model and weights: Xuebin Qin et al., "U²-Net: Going Deeper with Nested
  U-Structure for Salient Object Detection", https://github.com/xuebinqin/U-2-Net
- License: Apache License 2.0
- Source: the ONNX export distributed by rembg
  (https://github.com/danielgatis/rembg, release v0.0.0, MIT), SHA-256
  309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8,
  converted with onnx2tf 1.27.10 (TensorFlow 2.19) to TFLite with float16
  weights. Its masks differ from the ONNX model's by 0.1–0.4 % on average.
- SHA-256 of this file: 3360bf317f7615b13d679d933c88b70a37775525ad7921d7f7866cdafa9b163e

Input: 1×320×320×3 float (NHWC), RGB scaled to 0–1, divided by its maximum,
then normalized with the ImageNet mean/std. Output `Identity`: the 320×320
saliency map.
