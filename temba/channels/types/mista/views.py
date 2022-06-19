from smartmin.views import SmartFormView

from django import forms
from django.utils.translation import gettext_lazy as _

from temba.utils.fields import SelectWidget

from ...models import Channel
from ...views import ClaimViewMixin


class ClaimView(ClaimViewMixin, SmartFormView):
    class Form(ClaimViewMixin.Form):
        phonenumber = forms.CharField(max_length=12, min_length=1, help_text=_("Your Phone number or short code on Mista"))
        widget=SelectWidget(attrs={"searchable": True}),
        
     
       
        api_key = forms.CharField(max_length=64, help_text=_("Your api key, should be 64 characters"))

    form_class = Form

    def form_valid(self, form):
        user = self.request.user
        org = user.get_org()

        data = form.cleaned_data

        config = dict(api_key=data["api_key"])

        self.object = Channel.create(
            org,
            user,
            'RW',
            self.channel_type,
            name="Mista: %s" % data["phonenumber"],
            address=data["phonenumber"],
            config=config,
        )

        return super().form_valid(form)
