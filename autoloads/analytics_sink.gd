class_name AnalyticsSink
extends RefCounted
## Injectable analytics destination seam (S4-007, ADR-0014 §1).
##
## [AnalyticsService] forwards consent-approved events to an instance of this class. This
## base class is a deliberate [b]no-op[/b]: [method track] drops the event — the correct
## "no analytics vendor wired" behaviour this sprint. The real vendor SDK (Firebase /
## GameAnalytics / etc.) is a future subclass injected via [method AnalyticsService.configure],
## with zero changes to the service. Tests inject [MockAnalyticsSink] to capture events.
##
## The interface is intentionally vendor-agnostic: a string event name + a flat properties
## dictionary, so the funnel events ([AnalyticsService] constants) map onto any backend.
##
## Source: ADR-0014 §1 (uniform seam); production/sprints/sprint-04.md S4-007 (M5 prep).


## Records one analytics event. [param event_name] is a vendor-agnostic identifier;
## [param properties] is a flat dictionary of event attributes. The base implementation
## drops the event (no vendor). Implementations MUST be safe to call repeatedly.
func track(_event_name: String, _properties: Dictionary) -> void:
	pass


## [b]Test double.[/b] Captures every forwarded event in [member events] so tests can assert
## what reached the sink (and, by absence, what consent gating suppressed).
class MockAnalyticsSink extends AnalyticsSink:
	## Captured events, in order; each is [code]{ "name": String, "props": Dictionary }[/code].
	var events: Array = []

	func track(event_name: String, properties: Dictionary) -> void:
		events.append({"name": event_name, "props": properties})
