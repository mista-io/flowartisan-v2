# Generated by Django 4.0.3 on 2022-03-10 17:56

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ("orgs", "0093_squashed"),
        ("airtime", "0020_squashed"),
    ]

    operations = [
        migrations.AddField(
            model_name="airtimetransfer",
            name="org",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.PROTECT, related_name="airtime_transfers", to="orgs.org"
            ),
        ),
    ]
