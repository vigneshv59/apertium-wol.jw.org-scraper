1. Run `bundle install`
2. Run `bundle exec ruby scraper.rb` with the following arguments

         Usage: scraper.rb [options] lang1 lang2
           -o, --out=OUTPUT                 The out file name. (Mandatory)
           --date=DATE                      The date range, format YYYY-MM-DD:YYYY-MM-DD. (Mandatory)
           -a, --add                        Set this flag if you want to add to an existing file (passed as OUTPUT)
