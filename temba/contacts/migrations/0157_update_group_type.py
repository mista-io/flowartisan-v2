# Generated by Django 4.0.3 on 2022-03-24 16:20

from django.db import migrations


def update_group_type(apps, schema_editor):  # pragma: no cover
    ContactGroup = apps.get_model("contacts", "ContactGroup")
    num_updated = 0

    while True:
        batch = list(ContactGroup.all_groups.filter(group_type="U").only("id", "group_type", "query")[:1000])
        if not batch:
            break

        type_query, type_manual = [], []
        for g in batch:
            if g.query:
                type_query.append(g)
            else:
                type_manual.append(g)

        ContactGroup.all_groups.filter(id__in=[g.id for g in type_query]).update(group_type="Q")
        ContactGroup.all_groups.filter(id__in=[g.id for g in type_manual]).update(group_type="M")
        num_updated += len(batch)

    if num_updated:
        print(f"Updated group_type on {num_updated} contact groups")


def reverse(apps, schema_editor):  # pragma: no cover
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("contacts", "0156_alter_contactgroup_group_type_and_more"),
    ]

    operations = [migrations.RunPython(update_group_type, reverse)]
