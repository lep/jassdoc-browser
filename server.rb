#!/usr/local/bin/ruby

require 'sinatra'
require 'sqlite3'

require 'net/http'
require 'uri'
require 'json'

use Rack::Deflater


configure :production do
    set :root, "/usr/local/etc/jassdoc"
    set :bind, "192.168.1.18"
    set :port, 81
end

configure :development do
    set :bind, "0.0.0.0"
end

$db = SQLite3::Database.new "jass.db"

def pretty_args(args)
    return "nothing" unless args
    return args.map{ |v| v.join(" ") }.join(", ")
end

def pretty(v)
    c = v[0] == "Const" ? "constant" : ""
    t = v[1] == "Native" ? "native" : "function"
    n = v[2]
    a = pretty_args v[3]
    r = v[4]
    return [c, t, n, "takes", a, "returns", r].join(" ")
end

get '/api' do
    query = params['query']
    uri = URI('http://127.0.0.1:3000/api?query=' + query)
    data = Net::HTTP.get(uri)
    headers "Content-Type" => "text/json"
    body data
end

get '/search' do
    query = params['query']
    if not query
        erb :search, :locals => { :search => false }
    else
        uri = URI(url('/api?query='+ query))
        data = JSON.parse(Net::HTTP.get(uri))
        data = data.map { |x| pretty x[1] }
        erb :search, :locals => { :search => true, :results => data }
    end

end

get '/doc/:fn' do |fn|
    line = $db.execute "select value from annotations where fnname == ? and anname == 'start-line'", fn
    line = line[0][0]

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

    query = <<SQL
        select anname, value
        from annotations
        where fnname == ? and anname not in ('start-line', 'end-line')
        order by anname
SQL
    annotations = $db.execute query, fn


    # the :tables => true does nothing, have to pass it in erb file aswell
    erb :doc, { :no_intra_emphasis => true, :tables => true },
              { :annotations => annotations,
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
