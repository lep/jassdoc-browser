#!/usr/local/bin/ruby

require 'sinatra'
require 'sqlite3'

$db = SQLite3::Database.new "jass.db"

configure :production do
    set :root, "/usr/local/etc/jassdoc"
    set :bind, "192.168.1.18"
    set :port, 81
end

get '/doc/:fn' do |fn|
    comment = $db.execute "select comment from comments where fnname == ?", fn
    comment = comment[0][0] rescue "No Description yet"

    #parameters = $db.execute "select param, value from parameters where fnname == ?", fn
    #parameters = $db.execute "select param, value from parameters natural left join params_by_index where fnname == ? AND parameters.param == params_by_index.argname ORDER BY idx", fn
    query = <<SQL
        SELECT P.param, P.value, T.value
	FROM parameters AS P

	INNER JOIN
	( SELECT param, value
          FROM params_extra
	  WHERE anname == 'param_order' AND fnname == ?
	) AS Ord ON P.param == Ord.param

	INNER JOIN
	( SELECT param, value
	  FROM params_extra
	  WHERE anname == 'param_type' AND fnname == ?
	) AS T ON P.param == T.param

	WHERE fnname == ?
	ORDER BY Ord.value
SQL
    parameters = $db.execute query, [fn, fn, fn]
    annotations = $db.execute "select anname, value from annotations where fnname == ? order by anname", fn


    erb :doc, :no_intra_emphasis => true,
              :locals => { :annotations => annotations,
                          :parameters   => parameters,
                          :comment      => comment,
                          :fnname       => fn
                         }
end

get '/' do
	"gtfo"
end

get '*' do
	"gtfo"
end
