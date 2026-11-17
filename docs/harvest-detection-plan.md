# Harvest detection plan

Goal: the app tells you when the oyster mushrooms are ready to harvest, from photos taken inside the grow room.

```
ESP32-CAM --photo every 1-2 h--> Firebase Realtime DB --> Your app
                                                            |
                                         runs the image model (TFLite) on the photo
                                                            |
                                         "Ready" 2 photos in a row -> notification
```

### Step 1. Set up the camera

- Mount the ESP32-CAM in a fixed position, about 30–50 cm from the bags, aimed at the same bags every time. Do not move it after you start collecting photos.
- Put it inside a small clear box or cover the board with a plastic shield; the humidity will damage a bare board. Keep the lens clear (fog = blurry photos).
- Light: turn on the grow LED (or the onboard flash LED) just before each photo so every photo has the same lighting.
- Power it from your 5V buck converter (needs a stable 5V, at least 1A).

### Step 2. ESP32-CAM firmware (Arduino IDE)

Every 1–2 hours:
1. Turn on the light, wait 2 s.
2. Capture a JPEG at **VGA (640×480)**, quality ~12. This is around 20–40 KB.
3. Convert to base64 and write it to Realtime DB at `farm1/camera/latest` with a timestamp.
4. Also save a copy to `farm1/camera/history/<timestamp>`; keep only the last ~20 to save space.
5. Turn off the light and go to deep sleep until the next photo.

Why Realtime DB and not Firebase Storage: new Firebase projects now need the paid Blaze plan to use Storage. Small base64 photos in Realtime DB stay within the free Spark plan.

Libraries: `esp32-camera` (built into the ESP32 board package), `Firebase ESP Client` (Mobizt), `base64` (built in).

### Step 3. Collect training photos

**Start with public datasets so the feature works from day one**, then add your own photos to improve accuracy:
- Mendeley "Annotated Oyster Mushroom Images": 555 raw images, 8,000+ maturity-labeled images, plus environment sensor data. https://data.mendeley.com/datasets/hf55tkx489/1 (license not shown on the page; confirm before use and cite it in the thesis).
- Roboflow "IoT mushroom machine learning": classes `Pinhead` and `Harvest`, CC BY 4.0. https://universe.roboflow.com/umpsa-twe6u/iot-mushroom-machine-learning
- These are bounding-box (detection) datasets, so train a YOLOv8n model in Roboflow or Ultralytics and export to TFLite instead of Teachable Machine.

Then add your own farm photos:

- Let the camera run through 2–3 full fruiting cycles and save all the photos. You can also add phone photos taken from the same angle.
- Sort them into folders:
  - `not_ready`: pins and young clusters, caps still round and small
  - `ready`: caps flattened, edges still slightly curled down
  - `over_mature`: edges curled up or wavy, spores visible, drying
  - `empty`: no mushrooms yet (spawn run or right after harvest)
- Aim for **at least 100 photos per class**. Include different days, bags, and slight lighting differences.
- Ask whoever harvests to label honestly: the harvest day photos are your best "ready" examples.

### Step 4. Train the model

Easiest: **Teachable Machine** (teachablemachine.withgoogle.com)
1. Create an "Image Project", standard image model.
2. Make 4 classes with the names above and upload each folder.
3. Train, then test with photos you did not upload. If "ready" and "not_ready" get mixed up, add more photos of the in-between stage.
4. Export as **TensorFlow Lite** (floating point or quantized). You get `model.tflite` and `labels.txt`.

Alternative: **Edge Impulse** if you later want the model to run on the ESP32-S3 itself instead of the phone.

### Step 5. Use the model in your app

Flutter example:
- Packages: `firebase_database`, `tflite_flutter`, `image`, `flutter_local_notifications`.
- Put `model.tflite` and `labels.txt` in the app's assets.
- Listen to `farm1/camera/latest`. When a new photo arrives:
  1. Decode base64 to an image, resize to **224×224**.
  2. Run the model and get a score for each class.
  3. Save the result to `farm1/harvest/latest` (class, confidence, timestamp).
- Show the latest photo, the predicted stage, and its confidence on the dashboard.

Notification rule (avoids false alarms):
- If the result is `ready` with confidence **≥ 0.8** on **2 photos in a row**, show "Ready to harvest".
- If it is `over_mature`, show an urgent alert.

Note: push notifications when the app is closed need Firebase Cloud Messaging plus Cloud Functions, which require the Blaze plan. On the free plan, use local notifications while the app is running in the background, or do the check on a small always-on device later.

### Step 6. Combine with the timer (more reliable)

- In the app, let the farmer tap "Pinning started" for each batch.
- Days 5–7 after pinning: the app checks the camera result more closely and reminds the farmer even if the model is unsure.
- After harvest, the farmer taps "Harvested" and can enter the weight. This data improves the next training round.

### Parts for this feature

- ESP32-CAM with OV2640 Camera: 1 pc
- ESP32-CAM-MB Programmer Board: 1 pc
- Small clear plastic box for the camera: 1 pc
- Optional: HX711 with 5kg Load Cell: 1 set
