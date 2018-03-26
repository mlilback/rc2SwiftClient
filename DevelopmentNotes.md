# Development Notes

### Reactive Programming

* In SPs that have no value, always send an empty tuple as a value. Otherwise, any observer listening for a result will never be triggered.

### Notebook editor

* not using invalidationcontext because should never be enough chunks that resizing should cause a performance issue
