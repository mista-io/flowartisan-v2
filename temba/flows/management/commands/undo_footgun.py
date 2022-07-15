from collections import defaultdict

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from temba.contacts.models import Contact, ContactGroup
from temba.flows.models import FlowRun, FlowSession, FlowStart
from temba.utils import chunk_list


class Command(BaseCommand):
    help = "Attempts undo-ing of events generated by a flow start"

    batch_size = 100

    def add_arguments(self, parser):
        parser.add_argument("--start", type=int, action="store", dest="start_id", help="ID of flow start")
        parser.add_argument("--event", action="append", dest="event_types", help="Event types to include")
        parser.add_argument(
            "--dry-run", action="store_true", dest="dry_run", help="Whether to run without making actual changes"
        )
        parser.add_argument("--quiet", action="store_true", dest="quiet")

    def handle(self, start_id: int, event_types: list, dry_run: bool, quiet: bool, *args, **options):
        start = FlowStart.objects.filter(id=start_id).first()
        if not start:
            raise CommandError("no such flow start")

        undoers = {t: clazz(self.stdout) for t, clazz in UNDO_CLASSES.items() if not event_types or t in event_types}

        undo_types = ", ".join(sorted(undoers.keys())) if undoers else "no"
        desc = f"{undo_types} events for start #{start.id} of '{start.flow}' flow in the '{start.org.name}' workspace"
        if quiet:
            self.stdout.write(f"Undoing {desc}...")
        else:
            if input(f"Undo {desc}? [y/N]: ") != "y":
                return

        self.stdout.write("Fetching run ids... ", ending="")
        run_ids = list(start.runs.values_list("id", flat=True))
        self.stdout.write(f"found {len(run_ids)}")

        num_fixed = 0

        # process runs in batches
        for run_id_batch in chunk_list(run_ids, self.batch_size):
            run_batch = list(FlowRun.objects.filter(id__in=run_id_batch).only("id", "contact_id", "session_id"))

            self.undo_for_batch(run_batch, undoers, dry_run)
            num_fixed += len(run_batch)

            self.stdout.write(f" > Fixed {num_fixed} contacts")

        # print summaries of the undoers
        for undoer in undoers.values():
            undoer.print_summary()

    def undo_for_batch(self, runs: list, undoers: dict, dry_run: bool):
        contact_ids = {r.contact_id for r in runs}
        session_ids = {r.session_id for r in runs}

        if undoers:
            contacts_by_uuid = {str(c.uuid): c for c in Contact.objects.filter(id__in=contact_ids)}

            for session in FlowSession.objects.filter(id__in=session_ids):
                contact = contacts_by_uuid[str(session.contact.uuid)]
                for run in reversed(session.output_json["runs"]):
                    for event in reversed(run["events"]):
                        undoer = undoers.get(event["type"])
                        if undoer:
                            undoer.undo(contact, event, dry_run)

        if not dry_run:
            # update modified_on so indexer and dashboards see these changes
            Contact.objects.filter(id__in=contact_ids).update(modified_on=timezone.now())


class ContactGroupsChanged:
    def __init__(self, stdout):
        self.stdout = stdout
        self.removals = defaultdict(int)
        self.readds = defaultdict(int)

    def undo(self, contact: Contact, event: dict, dry_run: bool):
        uuids_added = [g["uuid"] for g in event.get("groups_added", [])]
        if uuids_added:
            groups = ContactGroup.objects.filter(uuid__in=uuids_added)
            memberships = ContactGroup.contacts.through.objects.filter(contact=contact, contactgroup__in=groups)
            if dry_run:
                names = [m.contactgroup.name for m in memberships]
                self.stdout.write(f"   - contact {contact.uuid} removed from groups {', '.join(names)}")
            else:
                memberships.delete()

            for name in [g["name"] for g in event.get("groups_added", [])]:
                self.removals[name] += 1

        uuids_removed = [g["uuid"] for g in event.get("groups_removed", [])]
        if uuids_removed:
            groups = ContactGroup.objects.filter(uuid__in=uuids_removed)
            if dry_run:
                self.stdout.write(f"   - contact {contact.uuid} re-added to {', '.join([g.name for g in groups])}")
            else:
                contact.groups.add(*groups)

            for name in [g["name"] for g in event.get("groups_removed", [])]:
                self.readds[name] += 1

    def print_summary(self):
        self.stdout.write("Removed contacts from groups:")
        for name, count in self.removals.items():
            self.stdout.write(f" > '{name}': {count}")
        self.stdout.write("Re-added contacts to groups:")
        for name, count in self.readds.items():
            self.stdout.write(f" > '{name}': {count}")


class ContactStatusChanged:
    def __init__(self, stdout):
        self.stdout = stdout
        self.num_reverts = 0

    def undo(self, contact: Contact, event: dict, dry_run: bool):
        new_status = event["status"]
        if dry_run:
            self.stdout.write(f"   - contact {contact.uuid} reverted from {new_status} to active")
        else:
            contact.status = Contact.STATUS_ACTIVE
            contact.save(update_fields=("status",))

        self.num_reverts += 1

    def print_summary(self):
        self.stdout.write(f"Reverted contacts to active status: {self.num_reverts}")


UNDO_CLASSES = {
    "contact_groups_changed": ContactGroupsChanged,
    "contact_status_changed": ContactStatusChanged,
}