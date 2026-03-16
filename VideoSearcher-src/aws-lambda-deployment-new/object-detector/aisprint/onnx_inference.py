# In Lambda, we don't need AI-SPRINT's orchestration.
import onnxruntime

def load_and_inference(onnx_model_path, input_dict):
    """
    Load ONNX model and run inference.

    Args:
        onnx_model_path: Path to the ONNX model file
        input_dict: Dictionary containing:
            - Input tensor (key matches model input name)
            - "image_source": Original image (pass-through)
            - "keep": Boolean flag (not used in Lambda)

    Returns:
        return_dict: Copy of input_dict (pass-through data)
        detections: ONNX model output (detections)
    """
    # Create ONNX Runtime session
    session = onnxruntime.InferenceSession(onnx_model_path)

    # Get input name from the session
    input_name = session.get_inputs()[0].name

    # Prepare input for ONNX Runtime (only the actual tensor data)
    onnx_inputs = {input_name: input_dict[input_name]}

    # Run inference - YOLO models output multiple detection scales
    # Returns list of outputs: [large_scale, medium_scale, small_scale]
    detections = session.run(None, onnx_inputs)

    # Return input_dict as return_dict (for pass-through data like image_source)
    # and ALL detection outputs from the model (list of tensors at different scales)
    return_dict = {k: v for k, v in input_dict.items() if k != input_name and k != "keep"}

    return return_dict, detections
