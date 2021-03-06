# Generated by Django 4.0.4 on 2022-04-27 20:24

from collections import defaultdict

from django.db import migrations, transaction
from django.db.models.functions import Lower


def make_flow_names_unique(apps, schema_editor):  # pragma: no cover
    Org = apps.get_model("orgs", "Org")  # noqa

    for org in Org.objects.all():
        with transaction.atomic():
            active_flows = org.flows.filter(is_system=False, is_active=True).order_by(Lower("name"), "created_on")
            unique_names = set()
            by_unique_name = defaultdict(list)

            for f in active_flows:
                unique_names.add(f.name.lower())
                by_unique_name[f.name.lower()].append(f)

            for unique_name, flows in by_unique_name.items():
                if len(flows) > 1:
                    for f in flows[1:]:
                        count = 2
                        count_str = f" {count}"
                        new_name = f"{f.name[:64 - len(count_str)]}{count_str}"
                        while new_name.lower() in unique_names:
                            count += 1
                            count_str = f" {count}"
                            new_name = f"{f.name[:64 - len(count_str)]}{count_str}"

                        print(f" > org '{org.name}' flow {f.uuid} '{f.name}' renamed to '{new_name}'")

                        f.name = new_name
                        f.save(update_fields=("name",))

                        unique_names.add(new_name.lower())


def reverse(apps, schema_editor):  # pragma: no cover
    pass


def apply_manual():  # pragma: no cover
    from django.apps import apps

    make_flow_names_unique(apps, None)


class Migration(migrations.Migration):

    dependencies = [
        ("flows", "0282_alter_flow_name"),
    ]

    operations = [migrations.RunPython(make_flow_names_unique, reverse)]
