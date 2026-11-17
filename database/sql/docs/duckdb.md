duckdb
只是想测试 SQL 语法，而不涉及 BigQuery 的云端特性，可以用 SQLite 或 DuckDB 进行本地 SQL 语法测试：

brew install duckdb

然后在 DuckDB 中测试 SQL 语句：

==> Fetching duckdb
==> Downloading https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/duckdb-1.2.1.arm64_sequoia.bottle.tar.gz
#################################################################################################################################################################################### 100.0%
==> Pouring duckdb-1.2.1.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/duckdb/1.2.1: 1,217 files, 158.3MB
==> Running `brew cleanup duckdb`...
Disable this behaviour by setting HOMEBREW_NO_INSTALL_CLEANUP.
Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`).


duckdb
v1.2.1 8e52ec4395
Enter ".help" for usage hints.
Connected to a transient in-memory database.
Use ".open FILENAME" to reopen on a persistent database.
D .help
.bail on|off             Stop after hitting an error.  Default OFF
.binary on|off           Turn binary output on or off.  Default OFF
.cd DIRECTORY            Change the working directory to DIRECTORY
.changes on|off          Show number of rows changed by SQL
.check GLOB              Fail if output since .testcase does not match
.columns                 Column-wise rendering of query results
.constant ?COLOR?        Sets the syntax highlighting color used for constant values
.constantcode ?CODE?     Sets the syntax highlighting terminal code used for constant values
.databases               List names and files of attached databases
.decimal_sep SEP         Sets the decimal separator used when rendering numbers. Only for duckbox mode.
.dump ?TABLE?            Render database content as SQL
.echo on|off             Turn command echo on or off
.excel                   Display the output of next command in spreadsheet
.edit                    Opens an external text editor to edit a query.
.exit ?CODE?             Exit this program with return-code CODE
.explain ?on|off|auto?   Change the EXPLAIN formatting mode.  Default: auto
.fullschema ?--indent?   Show schema and the content of sqlite_stat tables
.headers on|off          Turn display of headers on or off
.help ?-all? ?PATTERN?   Show help text for PATTERN
.highlight [on|off]      Toggle syntax highlighting in the shell on/off
.highlight_colors [element] [color]  ([bold])? Configure highlighting colors
.highlight_errors [on|off] Toggle highlighting of errors in the shell on/off
.highlight_results [on|off] Toggle highlighting of results in the shell on/off
.import FILE TABLE       Import data from FILE into TABLE
.indexes ?TABLE?         Show names of indexes
.keyword ?COLOR?         Sets the syntax highlighting color used for keywords
.keywordcode ?CODE?      Sets the syntax highlighting terminal code used for keywords
.large_number_rendering all|footer|off Toggle readable rendering of large numbers (duckbox only)
.log FILE|off            Turn logging on or off.  FILE can be stderr/stdout
.maxrows COUNT           Sets the maximum number of rows for display (default: 40). Only for duckbox mode.
.maxwidth COUNT          Sets the maximum width in characters. 0 defaults to terminal width. Only for duckbox mode.
.mode MODE ?TABLE?       Set output mode
.nullvalue STRING        Use STRING in place of NULL values
.once ?OPTIONS? ?FILE?   Output for the next SQL command only to FILE
.open ?OPTIONS? ?FILE?   Close existing database and reopen FILE
.output ?FILE?           Send output to FILE or stdout if FILE is omitted
.print STRING...         Print literal STRING
.prompt MAIN CONTINUE    Replace the standard prompts
.quit                    Exit this program
.read FILE               Read input from FILE
.rows                    Row-wise rendering of query results (default)
.safe_mode               Enable safe-mode
.schema ?PATTERN?        Show the CREATE statements matching PATTERN
.separator COL ?ROW?     Change the column and row separators
.shell CMD ARGS...       Run CMD ARGS... in a system shell
.show                    Show the current values for various settings
.system CMD ARGS...      Run CMD ARGS... in a system shell
.tables ?TABLE?          List names of tables matching LIKE pattern TABLE
.testcase NAME           Begin redirecting output to 'testcase-out.txt'
.thousand_sep SEP        Sets the thousand separator used when rendering numbers. Only for duckbox mode.
.timer on|off            Turn SQL timer on or off
.width NUM1 NUM2 ...     Set minimum column widths for columnar output


D .show
        echo: off
     headers: on
        mode: duckbox
   nullvalue: "NULL"
      output: stdout
colseparator: "|"
rowseparator: "\n"
       width: 
    filename: :memory:
D 