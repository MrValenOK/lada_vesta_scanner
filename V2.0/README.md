# VestaScan Pro V2.0

Диагностика Lada Vesta (ЭБУ Итэлма М86, UDS/KWP) через ELM327 Bluetooth Classic (SPP).

Собрано из двух проектов: `VestaScanPro` (новый каркас, проверяемый транспорт v1.4.1)
и `lada_vesta_scanner` (рабочие экраны и логика опроса, проверенные в автомобиле).

## Сборка

```
flutter pub get
flutter build apk --debug
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`

## Документы

- `AGENTS.md` — правила разработки и «наследие V2.0» (знание о плагине и транспорте).
- `plan.md` — рамки, сделанное, открытые шаги (A–F), техдолг.
- `PROGRESS.md` — журнал работ.
