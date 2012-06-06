### setup ###

    $ git clone git://github.com/sugyan/eyebeam-herokuapp.git
    $ cd eyebeam-herokuapp
    $ git submodule update --init
    $ bundle install
    $ foreman start

### for heroku ###

    $ heroku apps:create --stack cedar [NAME]
    $ heroku addons:add memcache
    $ heroku config:add KAOLABO_APIKEY=********************************
    $ heroku config:add TWITTER_CONSUMER_KEY=*********************
    $ heroku config:add TWITTER_CONSUMER_SECRET=****************************************
