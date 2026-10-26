-- Clip D1.1: the machine as the engine sees it. Runs on the lab, in one session; it only
-- reads. The cgroup limits of the container are read from a terminal (see the clip page):
--   docker exec sqloptcourse cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max
USE master;
SET NOCOUNT ON;
GO
-- Processors, memory and platform, as the engine counted them at startup.
SELECT cpu_count, socket_count, cores_per_socket, numa_node_count, scheduler_count,
       physical_memory_kb / 1024 AS physical_memory_mb,
       committed_target_kb / 1024 AS target_mb,
       committed_kb / 1024 AS committed_mb,
       container_type_desc, softnuma_configuration_desc
FROM sys.dm_os_sys_info;

SELECT host_platform, host_distribution, host_release
FROM sys.dm_os_host_info;

-- The nodes: two nodes that share the memory node 0 are soft-NUMA, a partition of the
-- schedulers made by the engine, not two memory banks.
SELECT node_id, node_state_desc, memory_node_id, online_scheduler_count
FROM sys.dm_os_nodes
WHERE node_state_desc NOT LIKE N'%DAC%';

-- The memory the engine sees and what is left of it.
SELECT total_physical_memory_kb / 1024 AS total_mb,
       available_physical_memory_kb / 1024 AS available_mb,
       system_memory_state_desc
FROM sys.dm_os_sys_memory;
GO
-- The MAXDOP that Microsoft's table gives for the processors and nodes the engine sees.
SELECT s.numa_node_count AS nodes,
       s.cpu_count AS logical_processors,
       s.cpu_count / s.numa_node_count AS processors_per_node,
       CASE
           WHEN s.numa_node_count = 1 AND s.cpu_count <= 8 THEN s.cpu_count
           WHEN s.numa_node_count = 1 THEN 8
           WHEN s.cpu_count / s.numa_node_count <= 16 THEN s.cpu_count / s.numa_node_count
           WHEN s.cpu_count / s.numa_node_count / 2 > 16 THEN 16
           ELSE s.cpu_count / s.numa_node_count / 2
       END AS recommended_maxdop,
       (SELECT CONVERT(int, c.value_in_use)
        FROM sys.configurations AS c
        WHERE c.name = N'max degree of parallelism') AS instance_maxdop
FROM sys.dm_os_sys_info AS s;
