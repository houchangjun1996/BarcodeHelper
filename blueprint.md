# Blueprint: Barcode Inspector v1.2

## 1. Overview

**Barcode Inspector** is a Flutter application designed for quality control on a production line. It validates barcodes on moving items against a set benchmark, counts successful (OK) and failed (NG) scans, and triggers an alarm for non-matching barcodes.

This version (**v1.2**) implements a **"Timed Capture + Offline Recognition"** system, which is robust for high-speed conveyor belts and offers precise control over the scanning frequency.

---

## 2. Core Features & Architecture

### Architecture: Timed Capture + Offline Recognition

- **State Management**: `provider` (via `ChangeNotifier`)
- **Camera Control**: `camera` package for low-level camera access and image capture.
- **Barcode Recognition**: `google_mlkit_barcode_scanning` for offline barcode analysis from captured images.

### Key Components:

- **`InspectionProvider`**: The core state management class.
  - Manages `CameraController` to interface with the device camera.
  - Runs a periodic `Timer` that triggers `takePicture()` at a user-defined interval.
  - On picture taken, it creates an `InputImage` and passes it to the `BarcodeScanner` from the ML Kit plugin.
  - Processes the recognition results, updates `OK`/`NG` counts, and manages the alarm state.
  - Handles data persistence using `shared_preferences`.

- **`InspectionScreen`**: The main UI.
  - Displays the `CameraPreview`.
  - Shows the benchmark code, OK/NG statistics, and control buttons.
  - Provides a dialog to **set the capture interval in milliseconds**.
  - Implements `WidgetsBindingObserver` to correctly handle the app's lifecycle (pausing/resuming the camera).

### Data Flow:

1.  **User sets a benchmark code and a capture interval (e.g., 200ms).**
2.  **User presses "Start Capturing".**
3.  A `Timer` starts, firing every 200ms.
4.  **On each tick:**
    - `cameraController.takePicture()` is called.
    - The resulting image (`XFile`) is held in RAM.
    - An `InputImage` is created from the file path.
    - `barcodeScanner.processImage()` analyzes the image.
    - The `XFile` and `InputImage` are implicitly garbage-collected after the analysis.
5.  **If a barcode is found:**
    - It's compared against the benchmark.
    - `OK` or `NG` count is incremented.
    - An alarm is triggered on NG.
6.  **User presses "Stop Capturing" to pause the timer.**

---

## 3. Style and Design

- **Theme**: Material 3 (Dark Mode).
- **Font**: `GoogleFonts.robotoMono` for a technical, monospaced look suitable for data display.
- **Color Scheme**:
  - **Primary**: `Colors.lightBlue` for accents and highlights.
  - **Success**: `Colors.green` for "OK" stats and active scanning indicators.
  - **Failure/Alarm**: `Colors.red` for "NG" stats and the flashing alarm background.
- **Layout**:
  - A clear top app bar.
  - A dedicated bar to display and edit the benchmark code.
  - A large, central area for the camera preview.
  - A stats panel with large, easy-to-read "OK" and "NG" cards.
  - A control panel with clearly labeled buttons for primary actions (Start/Stop, Reset, Set Interval).
  - A prominent "Stop Alarm" button that replaces the control panel during an alarm state.
- **Feedback**: 
  - **Visual**: The screen flashes red during an alarm.
  - **Audio**: An alarm sound (`alarm.mp3`) plays on loop during an alarm.

---

## 4. Current Task: Implement Timed Capture (v1.2)

**Plan:**

1.  **[DONE]** Remove `mobile_scanner`.
2.  **[DONE]** Add `camera` and `google_mlkit_barcode_scanning` to `pubspec.yaml`.
3.  **[DONE]** Restructure `main.dart`:
    - Initialize camera and pass it to `InspectionProvider`.
    - Rewrite `InspectionProvider` to manage `CameraController` and a `Timer`.
    - Implement the `_captureAndProcessImage` flow.
    - Add logic to update the capture interval (`updateCaptureInterval`).
4.  **[DONE]** Update the UI (`InspectionScreen`):
    - Replace `MobileScanner` with `CameraPreview`.
    - Add a button and dialog to configure the capture interval.
    - Update control buttons to `startCapturing`/`stopCapturing`.
    - Implement `WidgetsBindingObserver` for lifecycle management.
5.  **[NEXT]** Test the new implementation thoroughly.
6.  **[NEXT]** If successful, commit changes, build the APK, and create a new GitHub Release for v1.2.0.
