"""Read-only macOS Calendar via EventKit (lazy import; TCC prompt on first use)."""
import threading, time

NAME = "calendar"
PERMISSION = "calendars"
DESCRIPTION = ("Read the user's macOS calendar: today's date plus upcoming events "
               "for the next N days. Use for any question about schedule, meetings, or events.")
PARAMETERS = {
    "type": "object",
    "properties": {"days": {"type": "integer",
                            "description": "Days ahead to include, 1-31. Default 7."}},
    "required": [],
}

def run(days=7):
    from EventKit import EKEventStore, EKEntityTypeEvent  # lazy: ~nothing at startup
    from Foundation import NSDate
    today = time.strftime("Today is %A %Y-%m-%d.")
    store = EKEventStore.alloc().init()
    if EKEventStore.authorizationStatusForEntityType_(EKEntityTypeEvent) != 3:  # FullAccess (macOS 14+ value)
        done, ok = threading.Event(), []
        def _cb(granted, err):  # block returns void: must return None or pyobjc crashes
            ok.append(granted); done.set()
        store.requestFullAccessToEventsWithCompletion_(_cb)
        done.wait(30)  # user is looking at the TCC dialog
        if not (ok and ok[0]):
            return (today + " Calendar access not granted. The user must enable Calendar access "
                    "for C.I.E.L in System Settings > Privacy & Security > Calendars, then ask again.")
    days = max(1, min(int(days), 31))
    pred = store.predicateForEventsWithStartDate_endDate_calendars_(
        NSDate.date(), NSDate.dateWithTimeIntervalSinceNow_(days * 86400), None)
    events = sorted(store.eventsMatchingPredicate_(pred), key=lambda e: e.startDate().timeIntervalSince1970())
    if not events:
        return f"{today} No events in the next {days} days."
    lines = [f"{time.strftime('%a %m-%d %H:%M', time.localtime(e.startDate().timeIntervalSince1970()))} "
             f"{e.title()}" + (" (all day)" if e.isAllDay() else "")
             for e in events[:10]]
    more = f" (+{len(events) - 10} more)" if len(events) > 10 else ""
    return f"{today} Next {min(len(events), 10)} events{more}: " + "; ".join(lines)
