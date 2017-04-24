* Title: drphil.rb - Voting Bot - Windows Installation
* Tags: radiator ruby steem steemdev curation
* Notes: 

<div class="pull-right">
  <img src="http://i.imgur.com/MrXti1k.png" />
</div>

For these steps, we will install the `cygwin` package manager, which will provide the support packages and dependencies we need.

https://cygwin.com/

We need `cygwin` to install `git`, `ruby-dev`, `gem`, and `make` for us.  Run its setup and take all of the defaults, clicking `Next` until you reach the `Select Packages` dialog.  Select the `View` option of `Full`.  Search for:

* `git` and find the package named: `git: Distributed version control`.  Change `Skip` to `2.12.2-1` (or later).
* `ruby-dev` and find the package named: `ruby-devel: Interpreted object-oriented scripting language`.  Change `Skip` to `2.3.3-1` (or later).
* `gem` and find the package named: `rubygem: Ruby module management`.  Change `Skip` to `2.3.3-1` (or later).
* `make` and find the package named: `make: The GNU version of the 'make' utility`.  Change `Skip` to `4.2.1-1` (or later).

Click `Next` until `cygwin` is done installing these packages.

Open the `Cygwin Terminal`

Now, we can continue with the usual install:

```bash
$ git clone https://gist.github.com/61bcc2b821aa5acb24f7fc88921950c7.git drphil
$ cd drphil
$ bundle install
```

Then run it:

```bash
$ ruby drphil.rb
```

To configure `drphil`, you will need to modify the `drphil.yml` which will be located in:

`C:\cygwin\home\<username>\drphil`

---

If you're using Windows XP, official `cygwin` support has been dropped.  There is an unofficial project here:

http://www.crouchingtigerhiddenfruitbat.org/Cygwin/timemachine.html