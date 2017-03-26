* Title: drphil.rb - Voting Bot
* Tags: radiator ruby steem howto curation
* Notes: 

#### New Features

* Added YAML config.
  * `winfrey` mode that acts like the winfrey bot, all voters vote for everyone
  * `drphil` mode one random voter votes for everyone (default)
  * Added `min_rep` (default `25.0`)
  * Added `min_wait` and `max_wait` so that you can fine-tune voting delay.
* Skip posts with declined payout.
* Skip posts that already have votes from external scripts and posts that were edited.
* New argument called `replay:` allows a replay of *n* blocks allowing you to catch up to the present.
  * E.g.: `ruby drphil.rb replay:90` will replay the last 90 blocks (about 4.5 minutes).

#### Overview

Dr. Phil (`drphil.rb`) is reimplementation of the "Winfrey" voting bot specification.  The goal is to give everyone an upvote.

One optional improvement is that instead of voting 1% by 100 accounts like the Winfrey bot spec, this script can vote 100% with 1 randomly chosen account.

If the complaint about Winfrey is blockchain bloat, Dr. Phil prescribes weight loss to address this. But this feature would only work if there are enough voters defined in the script.  If you plan to use this script for one or two accounts, you'll probably want to adjust the `VOTE_WEIGHT` constant to something a bit lower.

---

#### Install

To use this [Radiator](https://steemit.com/steem/@inertia/radiator-steem-ruby-api-client) bot:

##### Linux

```bash
$ sudo apt-get install ruby-full git openssl libssl1.0.0 libssl-dev
$ gem install bundler
```

##### macOS

```bash
$ gem install bundler
```

I've tested it on various versions of ruby.  The oldest one I got it to work was:

`ruby 2.0.0p645 (2015-04-13 revision 50299) [x86_64-darwin14.4.0]`

First, clone this gist and install the dependencies:

```bash
$ git clone https://gist.github.com/61bcc2b821aa5acb24f7fc88921950c7.git drphil
$ cd drphil
$ bundle install
```

Then run it:

```bash
$ ruby drphil.rb
```

Dr. Phil will now do it's thing.  Check here to see an updated version of this bot:

https://gist.github.com/inertia186/61bcc2b821aa5acb24f7fc88921950c7

---

#### Upgrade

Typically, you can upgrade to the latest version by this command, from the original directory you cloned into:

```bash
$ git pull
```

Usually, this works fine as long as you haven't modified anything.  If you get an error, try this:

```
$ git stash --all
$ git pull --rebase
$ git stash pop
```

If you're still having problems, I suggest starting a new clone.

---

#### Troubleshooting

##### Problem: What does this error mean?

```
drphil.yml:3: syntax error, unexpected ':', expecting end-of-input
mode: winfrey
     ^
```

##### Solution: You ran `ruby drphil.yml` but you should run `ruby drphil.rb`.

---

<center>
  ![](https://cl.ly/1j1Z262a2A3d/Image%202017-03-22%20at%2012.17.22%20PM.png)
</center>

See my previous Ruby How To posts in: [#radiator](https://steemit.com/created/radiator) [#ruby](https://steemit.com/created/ruby)

## Get in touch!

If you're using Dr. Phil, I'd love to hear from you.  Drop me a line and tell me what you think!  I'm @inertia on STEEM.
  
## License

I don't believe in intellectual "property".  If you do, consider Dr. Phil as licensed under a Creative Commons [![CC0](http://i.creativecommons.org/p/zero/1.0/80x15.png)](http://creativecommons.org/publicdomain/zero/1.0/) License.
