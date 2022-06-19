from django.utils.translation import gettext_lazy as _
from django.urls import re_path

from temba.contacts.models import URN
from temba.utils.timezones import timezone_to_country_code

from ...models import ChannelType
from .views import ClaimView
RECOMMENDED_COUNTRIES = {
    "US",
    "CA",
    "GB",
    "AU",
    "AT",
    "FI",
    "DE",
    "HK",
    "RW",
    "LT",
    "NL",
    "NO",
    "PL",
    "SE",
    "CH",
    "BE",
    "ES",
    "ZA",
    "KE",
    "UG",
}

class MistaType(ChannelType):
    """
    Mista  channel (https://mista.io/)
    """
 

    code = "MX"
    category = ChannelType.Category.PHONE

    courier_url = r"^mx/(?P<uuid>[a-z0-9\-]+)/(?P<action>status|receive)$"

    name = "MISTA"
    icon = "icon-channel-external"

    claim_blurb = _("You can purchase a phone number or  short code from %(link)s and connect it in a few simple steps.") % {
        "link": """<a href="http://premium.mista.io">Mista.io</a>"""
    }
    claim_view = ClaimView

    schemes = [URN.TEL_SCHEME]
    max_length = 160
    attachment_support = False

    configuration_blurb = _(
        "To finish configuring your Mista connection you'll need to set the following callback URLs on the "
        "Mista website under your account."
    )

    configuration_urls = (
        dict(
            label=_("Callback URL"),
            url="http://{{ channel.callback_domain }}{% url 'courier.mx' channel.uuid 'receive' %}",
            description=_(
                "You can set the callback URL on your Mista account by visiting the SMS Dashboard page, "
                "then clicking on Callback URL."
            ),
        ),
        dict(
            label=_("Status URL"),
            url="http://{{ channel.callback_domain }}{% url 'courier.mx' channel.uuid 'status' %}",
            description=_(
                "You can set the delivery URL on your Mista account by visiting the SMS Dashboard page, "
                "then clicking on Delivery Reports."
            ),
        ),
    )

    available_timezones = [
       
        "Africa/Kigali"
     
    ]

    def is_recommended_to(self, user):
        org = user.get_org()
        country_code = timezone_to_country_code(org.timezone)
        return country_code in RECOMMENDED_COUNTRIES
