# Smart Mushroom Farming (IoT)

An ESP32-based controller for a mushroom grow room (humidity, CO2, temperature, water, light) with a mobile app connected through Firebase Realtime Database, plus ESP32-CAM harvest-readiness detection.

- [`handoff.md`](handoff.md): full project context, final parts list, architecture, decisions, open items. **Start here.**
- [`docs/parts-and-architecture.md`](docs/parts-and-architecture.md): detailed parts review, wiring cautions, database layout, setpoints.
- [`docs/harvest-detection-plan.md`](docs/harvest-detection-plan.md): camera + image model plan for "ready to harvest".
- [`docs/conversation-log.md`](docs/conversation-log.md): full planning conversation with the AI assistant, for context.

- [`firmware/original/`](firmware/original/): the students' original Arduino code (ESP32 controller + ESP32-S3 HMI), pin map and UART protocol.

Planned code layout: `firmware/controller/`, `firmware/hmi/`, `firmware/camera/`, `app/`, `ml/`.
