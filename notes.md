# SwiftClient

## MacClient

### Sessions and Dependency Injection

Ideally, the session should be injected into all relevant controllers. Apple suggests doing this in prepareForSeque(). However, that is not called in Mac apps using containment instead of transitions.

I see three possible ways to handle this:

* Use a singleton (which is not inversion of control)

* Have each controller walk the parent hierarchy looking for someone with the required property, and then getting the value from there. Notifications would have to be used for updating the value. (once again, not IoC)

* Have the top level controller walk all child controllers that conform to a protocol and set the value via the protocol. However, NSTabViewController lazily loads view controllers which eliminates this method for my use.


