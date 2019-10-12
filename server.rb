#!/usr/local/bin/ruby

require 'sinatra'
require 'sqlite3'

$db = SQLite3::Database.new "jass.db"

configure :production do
    set :root, "/usr/local/etc/jassdoc"
    set :bind, "192.168.1.18"
    set :port, 81
end

configure :development do
    set :bind, "0.0.0.0"
end

get '/doc/:fn' do |fn|

    query = <<SQL
select Ty.param, Ty.value, Doc.value
from
( select Value, param
  from Params_extra
  where Anname == 'param_order' AND fnname == ?
) as Ord

inner join
    ( select param, value
    from params_extra
    where anname == 'param_type' and fnname == ?
    ) as Ty on Ty.param == Ord.param

left outer join
    ( select param, value from parameters
      where fnname == ?
    ) as Doc on Doc.param == Ord.param

order by Ord.value
SQL
    parameters = $db.execute query, [fn, fn, fn]
    annotations = $db.execute "select anname, value from annotations where fnname == ? and anname not in ('start-line', 'end-line') order by anname", fn
    line = $db.execute "select value from annotations where fnname == ? and anname == 'start-line'", fn
    line = line[0][0]

    erb :doc, :no_intra_emphasis => true,
              :locals => { :annotations => annotations,
                           :parameters  => parameters,
                           :fnname      => fn,
                           :line        => line
                         }
end

get '/' do
    "gtfo"
end

get '*' do
    "gtfo"
end
