# Generated by Django 4.0.3 on 2022-03-31 20:49

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("triggers", "0023_squashed"),
    ]

    operations = [
        migrations.AlterModelOptions(
            name="trigger",
            options={"verbose_name": "Trigger", "verbose_name_plural": "Triggers"},
        ),
    ]
