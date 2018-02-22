# Development Notes

### Reactive Programming

* In SPs that have no value, always send an empty tuple as a value. Otherwise, any observer listening for a result will never be triggered.

