---
title: 图解MySQL读书笔记
date: 2023-09-13
categories: [读书笔记,MySQL]
tags: [读书笔记,mysql]
---

## 执行sql的流程

mysql是CS架构

- server端
  1. 连接器：用于和客户端建立连接和管理、通讯、鉴权等功能
  2. 查询缓存: 8之后没了
  3. 解析器：语法解析，判断是否正确，提取结构化信息
  4. 执行sql
    - 预处理：校验字段和表是否正确
    - 优化，生成执行计划：判断是否走索引
    - 执行器：配合存储引擎将进行数据查询和修改
- 存储引擎：实际真正执行sql的地方

![sql执行过程](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql/1692802104346.png)  

> 索引下推（index condition pushdown）：5.6的功能，存在联合索引的时候，比如idx_a_b_c，查询条件是a=1 and c=2，虽然c不走索引，但仍然可以在二级索引中筛选掉c的记录，减少回表次数，可以看到是将判断从server端下推到二级索引(using index condition)  
> 之前的流程是：server->二级索引->主键索引->server端判断是否满足条件c进行过滤  
> 现在的流程是：server->二级索引(同时判断是否满足条件c)->主键索引->server  

## 一行记录是怎么存储的

表数据是存在一个文件中，称为表空间文件
![表空间文件结构](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql/1693629727799.png)  

- 行：每行记录
- 页：数据库是按页从磁盘中读取数据的，一页大小为16KB，页有很多类型，如索引页、数据页、undo日志页、溢出页
- 区：将链表相邻的页也使其物理上相邻，这样可以将随机IO转为顺序IO了，所以表中数据量大的时候，不按页进行空间分配，而按区(1M,64个页)来划分空间
- 段：将数据分类，分为数据段、索引段、回滚段

### 行格式

- Redundant：5.0版本之前用的，非紧凑格式
- Compact：紧凑行格式，5.1之后默认
- Dynamic：5.7之后默认
- Compressed：后面两种格式都是差不多的，都是基于Compact格式做了一些改进

![Compact行格式结构](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql/1693708478931.png)  
- 记录额外信息
  - 变长字段长度列表：逆序排放，便于从记录头信息向左读时之际拿到相应信息，提高缓存命中率，下同，如果变长字段允许存储的最大字节数小于等于 255 字节，就会用1字节，否则用2字节
  - NULL值列表：逆序排放，至少8位，不足8位，高位补0，大于8位则使用16位(2字节)，以此类推，为什么不建议使用NULL？影响统计，至少占用1字节空间
  - 记录头信息：5字节
    - delete_mask：表示该记录是否删除
    - next_record：下一个记录头位置
    - record_type：表示当前记录的类型，0表示普通记录，1表示B+树非叶子节点记录，2表示最小记录，3表示最大记录
- 记录的真实数据
  - row_id：6字节，主键、唯一键或隐藏字段
  - tx_id：6字节，和下面的用于MVCC
  - roll_ptr：7字节
  - 值
- varchar(n)中n最大取值为多少？
一行数据的最大字节数65535，其实是包含「变长字段长度列表」和「NULL 值列表」所占用的字节数的

## 索引

### 索引分类

- 按数据结构分：B+树索引、Hash索引、Full-text索引
- 按物理存储分：聚簇索引(主键索引)、二级索引(辅助索引)
- 按字段特性分：主键索引、唯一索引、普通索引、前缀索引
- 按字段个数分：单列、联合索引

### 联合索引

- a是全局有序，b和c是全局无序，局部相对有序的，称之为最左匹配原则
- key_len可以查看命中联合索引的哪一部分，会加上变长字段长度列表和nul值列表，显示比较特殊，行格式是由innodb存储引擎实现的，而执行计划是在server层生成的，所以它不会去问innodb存储引擎可变字段的长度占用多少字节，而是不管三七二十一都使用2字节表示可变字段的长度。
- 为了便于判断新增数据插入到哪一个数据页，建立索引的时候最后都会加上id部分，所以在索引上按id排序可以避免filesort

### 索引缺点

- 占用物理空间
- 维护需要时间，降低增删改数据效率

### 索引建立原则

- 有唯一限制需求
- 区分度高(元素不同的个数多)
- 经常用于where、group by、order by查询的字段

### 索引失效原因

- 左模糊匹配，或非最左匹配
- 在索引列使用函数或表达式
- 非索引列使用or
- 优化器认为回表代价高时
- 使用order by，需要读进内存进行排序的数据过多时
- 隐式转换，类型不匹配的时候，mysql会自动将字符串转为数字，比如name=123，等同于cast(name)=123，导致不会走索引

### 索引优化

- 前缀索引，限制索引长度，但是order by和无法作为覆盖索引
- 覆盖索引，避免回表
- 主键索引自增，避免移动、页分裂、内存碎片、结构不紧凑等问题产生
- 避免使用NULL，可能导致统计复杂、占用空间

### explain

- id：id越大的先执行，id相同，从上往下执行
- type：避免前两种
  - All（全表扫描）；
  - index（全索引扫描）；
  - range（索引范围扫描）；
  - ref（非唯一索引扫描）；
  - eq_ref（唯一索引扫描）；
  - const（结果只有一条的主键或唯一索引扫描）。
- filtered：被索引过滤掉的数据百分比，`越大越好`
- rows：预估扫描的行数，越少越好
- extra
  - Using filesort：需要额外排序
  - Using temporary：使用了额外的临时表，效率比较低
  - Using index：覆盖索引
  - Using index condition：索引下推

### 为什么是B+树

- 相对于二叉树，高度比较低，需要的IO次数少
- 相对于B树(也是B-树)，主键索引的数据存在叶子节点，意味着匹配的时候需要加载到内存的数据少了，同时有一定冗余，在增删节点的时候操作相对简单，影响面小一些，并且支持范围查询

### 从数据页的角度看B+树

![数据页结构](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql/1693748815103.png)
![数据页7部分作用](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql/1693748967935.png)  
- 两个数据页通过在文件头的指针双向连接，是一个双向链表
- 数据页的页目录用于页内数据通过二分查找快速定位，是一个数组结构
- 数据页数据每个分组数据数不超过8条
![数据页页目录](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql/1693749084984.png)  
![数据页构成的B+树结构](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql/1693749193518.png)

## 为什么MySQL单表不要超过2000W行？

- 假设指针大小为6字节，主键为bitinit 8字节，16K字节-1K字节的文件头尾页头等信息
- 那么每个非叶子节点可以存储15k/(6+8)=1097条数据
- 假设每行数据大小为1KB，那么叶子节点可以存储15条数据，假设3层则：`1097*1097*15=1k800w`
- 查询树高：
```sql
SELECT
b.name, a.name, index_id, type, a.space, a.PAGE_NO
FROM
information_schema.INNODB_SYS_INDEXES a,
information_schema.INNODB_SYS_TABLES b
WHERE
a.table_id = b.table_id AND a.space <> 0;
```

> [InndoDB 单表最多 2000W，为什么？](https://www.cnblogs.com/crazymakercircle/p/17091391.html)

所以3次磁盘IO就可以覆盖2kw以内的，有前两层内存缓存的话，只要走一次磁盘IO就可以了，要是到四层就要2次磁盘IO相当于翻倍，所以性能会显著降低，但是随着现代内存、SSD等硬件的发展，一次磁盘IO带来的性能影响越来越小，2kw只是一个理论值，受表大小、设备硬件等因素决定

### 其他

- count(*)会转为count(0)，和count(1)执行流程一样，二级索引数据量相对于主键索引少一些，所以有二级索引count(*)会走二级索引，count(id)需要读取b+树的值，count(1)不需要，count函数不会读取null值
- 不需要精确值，可以使用show table status或explain统计

## 事务

### 事务的隔离级别是怎么实现的

- InnoDB 引擎通过什么技术来保证事务的ACID这四个特性的呢？
  - 持久性是通过 redo log （重做日志）来保证的；
  - 原子性是通过 undo log（回滚日志） 来保证的；
  - 隔离性是通过 MVCC（多版本并发控制） 或锁机制来保证的；
  - 一致性则是通过持久性+原子性+隔离性来保证；
![sql事务隔离级别标准](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql/1693843477058.png)  
- mysql中的RR级别很大程度上解决了幻读问题
- mysql通过快照读(MVCC)和当前读(select ... for update、增删改等通过net-key lock)部分解决幻读，但是先用快照读再用当前读的幻读仍然存在
![ReadView结构](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql/1694012787860.png)  
- m_ids：活跃的事务id列表
- min_trx_id：创建ReadView时，当前数据库中事务id最小的事务
- max_trx_id：下一个访问ReadView应赋予的事务id
- creator_trx_id：创建ReadView的事务id
![ReadView中事务id和事务提交关系](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql/1694012977002.png)  
![版本链条](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql/1694013218995.png)  
- RR下事务A未提交，事务B只能读到trx_id=50的数据
- RC下事务A已提交，m_ids中会移除51，事务B可以读到trx_id=51版本的数据

## 锁

### mysql锁种类

- 全局锁：用于数据备份，保证数据备份过程中整体一致，但会造成业务停滞，可借用事务的read view解决这个问题，mysqldump时可以加上 –single-transaction参数
  - 锁库`flush tables with read lock`
  - 解锁`unlock tables`
- 表级锁
  - 表锁：`lock tables t_student read/writer`，`unlock tables`，不可重入
  - 元数据所(MDL)：CRUD加MDL读锁、对表结构进行改变的时候加MDL写锁，避免有长事务的时候进行改变表结构，因为MDL写锁优先于MDL读锁，MDL写锁等待长事务释放期间，会一直阻塞其他sql的操作，造成业务停滞
  - 意向锁：目的是为了快速判断表里是否有记录被加锁，用表锁的时候就不用遍历所有记录锁，类似于一个缓存
  - AUTO-INC锁：`innodb_autoinc_lock_mode`可以配置模式0(等待事务执行才释放锁)，1(普通直接释放锁，批量需要等待事务释放锁)，2(默认，申请完就释放锁)，binlog模式日志格式为statement在主从复杂时会导致数据不一致的问题，配置binlog_format=row即可
- 行级锁
  - Record Lock，记录锁，仅锁一条数据
  - Gap Lock，间隙锁，锁定一个左开右开的范围
  - Net-key Lock，临键锁，锁定一个左开右闭的区间
- 插入意向锁：名字虽然有意向锁，但是它并不是意向锁，它是一种特殊的间隙锁，属于行级别锁，锁住的是将要插入的数据的key，和间隙锁冲突

### mysql是怎么加锁的

- RR隔离级别下加锁是为了解决幻读问题
- RC隔离级别下加锁是为了保证数据的安全性，如果没有锁，A事务先改的数据，未提交，然后B事务改数据提交了，这时A再提交事务，导致B的更改丢失了。这种情况会造成数据丢失和数据不一致，即`丢失更新`，最终目的还是为了ACID

可以通过`select * from performance_schema.data_locks\G;`语句查询锁占用信息
- LOCK_TYPE：锁类型
  - TABLE：表锁
  - RECORD：记录锁
- LOCK_MODE：锁模式
  - IX：意向锁
  - X(Exclusive)：临键锁
  - X,GAP：间隙锁
  - X,REC_NOT_GAP：记录锁
- Lock_DATA：X[,Y]，X为记录锁的右端点，Y在二级索引时表示主键

具体看sql，当前读语句默认加锁的单位是临键锁，这个`临键`的含义有两个，查询条件在索引上匹配时，匹配到的记录就是区间的右端点，即`键`；当查询条件无法匹配的时候，`临`的意思就是将扫描到的第一个不匹配的记录作为右端点，当出现以下情况下会退化成记录锁或间隙锁：
- 唯一索引等值匹配
  - 匹配上：记录锁
  - 未匹配：间隙锁
- 唯一索引范围匹配（大于等于情况）
  - 匹配上：记录锁+临键锁
  - 未匹配：临键锁
- 普通索引等值匹配：
  - 匹配上：临键锁(注意锁的端点会带上主键，因为普通索引值可重复，不具有唯一性，加上主键的话插入时是否冲突可以通过主键大小进行判断)、间隙锁
  - 未匹配：间隙锁
- 普通索引范围匹配（大于等于情况）
  - 匹配上：临键锁
  - 未匹配：临键锁
- 没有索引的加锁（比如update没加条件或where条件`没走(没索引或优化器不选择走)`索引会导致锁全表）
  - 按主键索引扫描顺序，依次加锁，这样才能解决幻读和防止`丢失更新`
> 注意mysql锁的时加到索引上的，不管是主键索引还是二级索引都会加锁，如果走二级索引，除了锁二级索引，还会将主键索引的记录锁住，防止直接进行主键更新，或通过其他索引更新主键索引

### 死锁

- insert默认不加锁，当和后续事务发生冲突时，会升级为X型的记录锁
  - 此时若其他事务操作为insert，那么该事务会持有S型的临键锁(视情况降级为记录锁)
- 若插入过程中发现有主键冲突，事务未退出的话，该事务还会持有S型的记录锁，猜测作用是防止其他事务删除了记录导致幻读
- insert期间发现有间隙锁，则会生成插入意向锁(LOCK_MODE=X,INSERT_INTENTION)，等待锁的获取，其他事务释放锁后，本事务则可正常获取到插入意向锁，当持有插入意向锁和其他所有锁是兼容的
- 间隙锁和间隙锁是兼容的(因为间隙锁是防止插入的，避免幻读问题，按id更新不会更新到不存在的数据中，除非更新的数据不存在或范围的)
![锁兼容矩阵](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql/1694614881876.webp)

## 日志

- undo log（回滚日志）：是Innodb存储引擎生成的日志，实现了事务中的原子性，主要用于`事务回滚和MVVC`
- redo log（重做日志）：是Innodb存储引擎生成的日志，实现了事务中的持久性，主要用于`掉电等故障恢复`
- binlog（归档日志）：是Server层生成的日志，主要用于`数据备份和主从复制`

### undo log

- 进行数据操作的时候会将操作的内容(新值、旧值)都记录下来，在回滚的时候用于恢复到原始的状态，保证了事务的原子性
- 更新生成的undo log会形成版本链，通过版本链，可以在不同事务隔离级别下形成不同的ReadView，实现可重复读和读已提交的功能

### Buffer Pool

缓存索引页、数据页、Undo页、插入缓存、自适应哈希索引、锁信息等等，以16KB一页为单位

### redo log

需要它的原因是前面为提高效率引入了存在内存的buffer pool，掉电或宕机的时候如果未落盘会导致数据丢失，所以mysql折中考虑使用了效率相对好一些的顺序连续io，即WAL（Write-Ahead Logging）日志技术
![redo log流程](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql%E8%AF%BB%E4%B9%A6%E7%AC%94%E8%AE%B0/1696214630042.png)
- undo log和redo log的区别是一个记录事务操作前的数据，一个记录事务操作完成之后的数据
- 最终实现了事务的持久性，让mysql有了crash-safe的能力，将写操作从随机写变成顺序写，提高mysql的写入性能
- redo log也不是直接写入磁盘的，后面还有一个redo log buffer
![redo log buffer](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql%E8%AF%BB%E4%B9%A6%E7%AC%94%E8%AE%B0/1696215141381.png)  
- redo log刷盘时机
  - mysql正常关闭时
  - redo log buffer写入量大于redo log buffer内存空间一半时
  - 每次事务提交时(可以通过innodb_flush_log_at_trx_commit控制，0为只写到用户内存，默认值1写到磁盘，2为只写到内核内存)
- 当innodb_flush_log_at_trx_commit取值为0或2的时候，InnoDB后台线程每隔1s会进行主动刷盘操作，所以针对0，mysql宕机可能操作丢失1s数据，针对2，mysql宕机不会丢失数据，操作系统宕机才会丢失数据
![innodb_flush_log_at_trx_commit参数行为](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql%E8%AF%BB%E4%B9%A6%E7%AC%94%E8%AE%B0/1696215625268.png)
![redo log循环写机制](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql%E8%AF%BB%E4%B9%A6%E7%AC%94%E8%AE%B0/1696215826296.png)  
![redo log写满后的处理流程](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql%E8%AF%BB%E4%B9%A6%E7%AC%94%E8%AE%B0/1696215860774.png)  

### binlog

![redo log和binlog区别](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql%E8%AF%BB%E4%B9%A6%E7%AC%94%E8%AE%B0/1696216090190.png)  
![mysql主从同步流程](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql%E8%AF%BB%E4%B9%A6%E7%AC%94%E8%AE%B0/1696216524010.png)  
![mysql主从复制模型](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql%E8%AF%BB%E4%B9%A6%E7%AC%94%E8%AE%B0/1696216475382.png)  
- 事务执行的过程中，会先写日志到binlog cache，在事务提交的时候写到磁盘，如果binlog cache不够大，会先写到磁盘中
![binlog写入磁盘流程](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql%E8%AF%BB%E4%B9%A6%E7%AC%94%E8%AE%B0/1696217030306.png)  
![bin log刷盘参数](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql%E8%AF%BB%E4%B9%A6%E7%AC%94%E8%AE%B0/1696217013248.png)  

### 两阶段提交

// TODO

### 总结

![更新一行数据mysql执行的逻辑操作](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql%E8%AF%BB%E4%B9%A6%E7%AC%94%E8%AE%B0/1696216714012.png)  
![mysql磁盘IO高的处理方法，主要时控制redo log和binlog的刷盘时机](https://storage.xqdd.cc/notes/images/%E7%AC%94%E8%AE%B0/JAVA/%E5%9B%BE%E8%A7%A3mysql%E8%AF%BB%E4%B9%A6%E7%AC%94%E8%AE%B0/1696217109446.png)

## buffer pool

> 默认大小128MB，可通过调整innodb_buffer_pool_size的大小来控制，一般建议设置成可用物理内存的60%~80%

为便于管理，buffer pool页由以下组织关系进行管理控制
- 空闲页链表(Free List)
- 脏页链表(Flush List)
- LRU List(管理脏页和干净页)：分为冷热数据(时间+访问次数)，防止短时间内批量访问造成的大量热数据被淘汰问题

## 中途加餐

### redolog和undolog

- redolog：将要更新的记录完整地维护到磁盘中(B+树、页结构)成本时比较大的，所以mysql为了提供吞吐和防止宕机随机读写磁盘不过来，会将数据变动以日志顺序写到一个专门的地方(Write-Ahead logging)，然后仅更新内存，之后再定时或批量处理redolog中的记录
- binglog：redolog是InnoDB存储引擎特有的日志, binlog是server层的日志，最初是没有redolog的

## 参考链接

- [图解MySQL](https://www.xiaolincoding.com/mysql/)
