# Generated by Django 4.0.4 on 2022-05-06 19:13

from django.db import migrations, models

import temba.utils.uuid


class Migration(migrations.Migration):

    dependencies = [
        ("campaigns", "0046_alter_campaign_name"),
    ]

    operations = [
        migrations.AlterField(
            model_name="campaign",
            name="uuid",
            field=models.UUIDField(default=temba.utils.uuid.uuid4, unique=True),
        ),
        migrations.AlterField(
            model_name="campaignevent",
            name="uuid",
            field=models.UUIDField(default=temba.utils.uuid.uuid4, unique=True),
        ),
    ]
