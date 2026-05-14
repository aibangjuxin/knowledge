对于Splunk服务端来说,要收集Splunk客户端Agent发送过来的数据,主要需要注意以下两点配置:

1. 输入端口配置

在服务端inputs.conf配置文件中,需要配置一个接收数据的端口,例如:

[tcp://9998]

然后在客户端也对应配置这个端口作为输出端口。

2. 数据索引配置

在服务端上需要确保接收的数据能够被正确索引和存储。这需要配置对应的index,例如default索引:

[default]
homePath = $SPLUNK_DB/default/db
coldPath = $SPLUNK_DB/default/colddb
thawedPath = $SPLUNK_DB/default/thaweddb

然后在props.conf等文件中配置sourcetype,使数据被发送到默认索引。

如果这两点配置正确,服务端就可以接收并索引客户端发送过来的数据了。

所以服务端主要是通过配置输入端口以及后端的存储和索引来支持数据的接收。客户端才是负责收集和发送数据的主要部分。服务端配置相对简单一些。

log.cfg 是 Splunk 在 Linux/Unix 系统下用于配置数据输入的一个重要配置文件。

log.cfg 文件主要包含两部分内容:

1. 数据输入配置

在这个文件中可以使用 [monitor://] 或 [tcp://] 协议来指定要监控和收集的数据文件,比如:

[monitor://var/log/messages] 
[tcp://514]

2. 数据处理配置

可以通过 sourcetype、host等参数来定义收集的数据的元信息,也可以使用 transforms 来处理事件数据。

例如:

[monitor://var/log/messages]
sourcetype=linux_messages
host=myhost

[tcp://514]
transforms=trans1

log.cfg 的配置会被默认引入到 inputs.conf 配置文件中。

所以通过配置 log.cfg 文件,可以方便的指定 Splunk 收集的日志文件、数据输入以及后续处理。它是 Splunk 在 Linux 系统下收集和解析日志的一个重要配置文件。文件位置通常在 /opt/splunk/etc/system/local/ 目录下。

Splunk Agent 在收集数据的时候,主要通过配置文件来指定要监控和收集哪些日志文件或数据。

常见的几种配置方式:

1. inputs.conf 配置文件

可以在这个配置文件中指定要监控的日志文件路径,以及是否监控标准输出和标准错误流等。通过 [monitor://] 或 [tcp://] 协议指定日志文件。

2. props.conf 配置文件 

可以通过这个文件指定日志格式,以及对某些日志文件指定独立的源类型和标记。

3. transforms.conf 配置文件

可以对日志数据进行转换,比如提取字段,删除无用信息等。

4. 是否开启内置数据类型

Splunk 有一些预定义的内置数据类型,可以自动提取常见日志格式的数据。比如 enableSplunkCommonLogging 可以自动提取 Apache 访问日志。

5. 配置数据输入端口

可以配置 Splunk Agent 在某个端口接收数据输入,然后通过各种方式将数据发送到这个端口。

6. 配置监控目录

可以简单的配置监控一个目录,Splunk 会自动监控该目录下所有文件的变化。

所以 Splunk Agent 收集数据的方式很灵活,核心还是通过配置文件来指定需要收集的数据源、处理方式等。日常使用中根据需要进行配置,来实现对不同数据源的收集。


对于Splunk服务端来说,在大多数情况下不需要关心Agent端的日志目录配置。

原因有以下几点:

1. Agent端负责收集和转发日志,它会处理日志的解析、加工等工作,然后以事件(Event)的格式发送给服务端。

2. 服务端通过输入端口接收事件数据,主要关心事件的数据格式和元数据(如sourcetype、host等),而不关系原始日志的目录路径。

3. 服务端索引事件数据时,是根据事件元数据来确定索引和分割存储的,而不是根据原始日志目录。

4. Search时,用户主要根据sourcetype、host等条件来查询,而不是指定日志目录。

5. Agent和服务端之间可以通过转发器(Forwarder)等中间层,进一步隔离两端的配置。

但是如果要跟踪某个事件的原始日志源,服务端也会记录_raw字段,存储原始日志内容。

所以简单来说,服务端不需要关心Agent的日志目录配置,只需要关心接收到的事件数据本身即可。但也不完全不相关,如果需要进行故障排查等还是需要跟Agent端协作。


