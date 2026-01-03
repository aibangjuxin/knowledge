
在 Linux 系统中，TCP Segmentation Offload (TSO) 是一种网络技术，旨在减轻 TCP 分段造成的 CPU 负载。它允许网络适配器直接将大型数据分段为最大数据分段长度，而不是由操作系统进行分段。这有助于减少 CPU 负载，提高处理性能。

TSO 的作用包括：

1. **减少 CPU 负载**：由于网络适配器直接进行数据分段，因此操作系统的 CPU 负载会降低。

2. **提高传输性能**：通过减少 CPU 负载，TSO 可以提高网络传输的性能。

3. **降低网络延迟**：由于网络适配器直接进行数据分段，因此网络延迟会降低。

要查看 TSO 的当前状态，您可以使用以下命令：

```bash
ethtool -K <interface> tso on
```

将 `<interface>` 替换为您要检查的网络接口名称。例如，如果您要检查 `eth0` 接口上的 TSO 状态，则可以使用以下命令：

```bash
ethtool -K eth0 tso on
```

如果 TSO 已启用，您将看到类似以下输出：

```bash
tso: on
```

如果 TSO 已禁用，您将看到类似以下输出：

```bash
tso: off
```

要启用 TSO，您可以使用以下命令：

```bash
ethtool -K <interface> tso on
```

这将启用 TSO 功能，使您的网络接口能够更有效地处理大型 TCP 数据包。请注意，在启用 TSO 功能之前，您可能需要确保您的网络接口和操作系统支持这一特性。

Citations:
[1] https://docs.nvidia.com/networking/display/rdmacore50/tcp%2Bsegmentation%2Boffload%2B%28tso%29
[2] https://www.baeldung.com/linux/tcp-offload-disable
[3] https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/performance_tuning_guide/network-nic-offloads
[4] https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-networking/GUID-E105A601-9331-496C-A213-F76EA3863E31.html
[5] https://serverfault.com/questions/1004458/how-to-verify-status-of-tcp-segmentation-offloading
[6] https://kb.vmware.com/s/article/2055140
[7] https://www.kernel.org/doc/Documentation/networking/segmentation-offloads.txt
[8] https://www.ibm.com/docs/en/linux-on-z?topic=offload-tcp-segmentation


TCP Large Send Offload (LSO) 是一种网络技术，旨在减轻 TCP 分段造成的 CPU 负载。它理论上可以改善传输性能，降低网络延迟。LSO 允许网络适配器在发送数据包时直接将数据分段为最大数据分段长度，而不是由操作系统进行分段。这有助于减少 CPU 负载，提高处理性能。


Citations:
[1] https://blog.csdn.net/wangyequn1124/article/details/103664856
[2] https://www.wavecn.com/content.php?id=363
[3] https://huataihuang.gitbooks.io/cloud-atlas/content/network/packet_analysis/tcpdump/udp_tcp_checksum_errors_from_tcpdump_nic_hardware_offloading.html
[4] https://ms2008.github.io/2018/06/01/tcp-troubleshooting/
[5] https://blog.csdn.net/maimang1001/article/details/120273632
[6] https://www.cnblogs.com/AllenWoo/p/16160796.html
[7] https://github.com/moooofly/MarkSomethingDown/blob/master/Linux/TCP%20%E4%B9%8B%20TSO%20GSO%20LSO.md
[8] https://blog.51cto.com/u_1923895/5939791


TCP 大型发送卸载选项允许 AIX® TCP 层创建长达 64 KB 的 TCP 报文。适配器通过 IP 和以太网设备驱动程序在堆栈中一次调用即可发送报文。

然后，适配器将报文分解成多个 TCP 帧，在电缆上传输数据。电缆上发送的 TCP 数据包要么是媒体传输单元 (MTU) 为 1500 的 1500 字节帧，要么是媒体传输单元 (MTU) 为 9000 的 9000 字节帧（巨帧）。

如果不使用 TCP 大型发送卸载选项，TCP 选项要发送 64 KB 的数据，就需要使用 1500 字节数据包在堆栈中进行 44 次调用。使用 TCP 大发送选项后，TCP 选项只需在堆栈中调用一次，就能发送多达 64 KB 的数据，从而减少了主机处理，降低了主机处理器的利用率。然后，以太网适配器进行 TCP 分段卸载，将数据分段为 MTU 大小的数据包（通常为 1500 字节）。节省的费用因 TCP 大发送量的平均大小而异。例如，使用 MTU 大小为 1500 的 PCI-eXtended (PCI-X) 千兆以太网适配器，主机处理器 CPU 可减少 60% 至 75%。对于巨型帧（MTU 9000），由于系统已经发送了较大的帧，因此节省的CPU较少。例如，使用巨型帧时，主机处理器 CPU 通常可减少 40%。

在专用模式下工作时，支持大发送卸载选项的以太网适配器默认启用该选项。对于管理数据流的工作负载（如文件传输协议 (FTP)、RCP、磁带备份和类似的批量数据移动应用），该选项可提高万兆以太网适配器和更高速适配器的性能。虚拟以太网适配器和共享以太网适配器 (SEA) 设备是例外情况，由于 Linux® 或 IBM i 操作系统的互操作性问题，默认情况下禁用大发送卸载选项。可以在 AIX 和虚拟以太网适配器或 SEA 环境中启用大型发送和其他性能功能。

大型发送选项是一个指定为 large_send 的设备属性。使用以下命令可以查看大型发送卸载设备属性，其中 X 为设备编号

https://www.ibm.com/docs/el/aix/7.1?topic=tuning-tcp-large-send-offload


To view the current setting of the TCP large send offload (TLS) property on AIX, you can use the `netstat` command with the `-i` option, which displays information about the network interfaces on the system[1][5]. Here's the command you can use:

```
netstat -i
```

This command will display a table with information about each network interface, including the current settings for various adapter offload options, such as TCP checksum offload and TCP large send or re-segmentation. Look for the `TX_OFFLOAD` column in the output, which indicates whether TLS is enabled (1) or disabled (0) on each interface.

Additionally, you can use the `ethtool` command to view and modify various network interface settings, including TLS. For example, to display the current TLS setting for a specific interface (let's say `eth0`), you can use the following command:

```
ethtool -k eth0 | grep tso
```

This command will display the current TLS setting for the `eth0` interface, along with other offload options. If TLS is enabled, the output will show `tso: on`, and if it's disabled, the output will show `tso: off`.

Note that TLS is enabled by default on 10 Gigabit Ethernet adapters and higher on AIX, but it may not be enabled on other types of network interfaces or on virtual Ethernet adapters and SEA devices due to interoperability problems with the operating system[1][2]. If you're using a virtual Ethernet adapter or SEA device, you may need to modify the configuration of the virtual NIC or the SEA device to enable TLS.

Finally, if you're using Red Hat Enterprise Linux (RHEL) on IBM Power, you can use the `ethtool` command to enable TLS for each connection in the LPARs. The `ethtool` command allows you to turn on TLS (also called large_send) on the veth driver, which is used for virtual Ethernet interfaces in RHEL on IBM Power[3]. To enable TLS for a specific interface (let's say `eth0`), you can use the following commands:

```
rmmod ibmveth // unload the veth driver
modprobe ibmveth old_large_send=1 // reload the veth driver with TLS enabled
ethtool -K eth0 tso on // turn on large_send on the interface
```

These commands will unload the veth driver, reload it with TLS enabled, and then enable TLS on the `eth0` interface. To verify that TLS is enabled, you can use the `ethtool -S` command to display the large_send and large_receive packet numbers for the interface.

Citations:
[1] https://www.ibm.com/docs/el/aix/7.1?topic=tuning-tcp-large-send-offload
[2] https://www.circle4.com/movies/edge2016/aixperf-part3.pdf
[3] https://access.redhat.com/articles/3169971
[4] https://www.ibm.com/support/pages/how-temporarily-enable-or-disable-large-send-offload-lso-ibm-i
[5] https://www.ibm.com/docs/en/aix/7.2?topic=performance-tcp-udp-tuning


在 Linux 主机上，可以使用 `ethtool` 命令来查看和设置 TCP large send offload (TSO) 的当前状态。首先，您可以使用以下命令查看 TSO 的当前状态：

```bash
ethtool -K <interface> tso on
```

将 `<interface>` 替换为您要检查的网络接口名称，例如 `eth0`。如果 TSO 已启用，您将看到类似以下输出：

```bash
tso: on
```

如果 TSO 已禁用，您将看到类似以下输出：

```bash
tso: off
```

如果您想启用 TSO，可以使用以下命令：

```bash
ethtool -K <interface> tso on
```

这将启用 TSO 功能，使您的网络接口能够更有效地处理大型 TCP 数据包。

请注意，TSO 的使用和支持取决于您的网络接口和操作系统版本。如果您的网络接口或操作系统不支持 TSO，您可能需要更新驱动程序或操作系统。

Citations:
[1] https://www.cnblogs.com/sammyliu/p/5227121.html
[2] https://sniffer.site/2019/01/17/linux%E4%B8%8B%E5%B8%B8%E7%94%A8%E7%BD%91%E7%BB%9C%E5%B7%A5%E5%85%B7%E4%BD%BF%E7%94%A8%E6%80%BB%E7%BB%93/
[3] https://blog.csdn.net/yunlianglinfeng/article/details/120458288
[4] http://xstarcd.github.io/wiki/sysadmin/lvs_network_delay_and_gro_lro.html
[5] https://lework.github.io/2020/02/20/network/
[6] https://jimizhou.com/virtual-network
[7] https://blog.51cto.com/u_10630401/4864216
[8] https://www.cnblogs.com/CasonChan/p/5166708.html
[9] https://www.cnblogs.com/zengkefu/p/7019872.html
[10] https://blog.csdn.net/rikeyone/article/details/108761544
[11] https://blog.csdn.net/sunny_jiangsu/article/details/96334911
[12] https://blog.csdn.net/qq_33745102/article/details/103699802
[13] https://blog.crazytaxii.com/posts/linux_network_performance_optimization_reference/
[14] https://liuhao163.github.io/%E7%B3%BB%E7%BB%9F%E4%BC%98%E5%8C%96-%E7%BD%91%E7%BB%9C-%E9%98%B6%E6%AE%B5%E6%80%A7%E6%80%BB%E7%BB%93/



如果您的 Linux 系统上的 ethtool 命令输出中显示了 `large-receive-offload: on`，则表明您的系统已启用了大型接收缓冲区，而您的对应的 `send` 可能未设置。要启用 `send`，您可以使用以下命令：

```bash
ethtool -K <interface> tso on
```

将 `<interface>` 替换为您要启用 `send` 的网络接口名称。例如，如果您要启用 `eth0` 接口上的 `send`，则可以使用以下命令：

```bash
ethtool -K eth0 tso on
```

这将启用 `send` 功能，使您的网络接口能够更有效地处理大型 TCP 数据包。请注意，在启用 `send` 功能之前，您可能需要确保您的网络接口和操作系统支持这一特性。

Citations:
[1] https://serverfault.com/questions/1004458/how-to-verify-status-of-tcp-segmentation-offloading
[2] https://docs.gz.ro/tuning-network-cards-on-linux.html
[3] https://www.linux-magazine.com/Issues/2016/182/Ethtool/%28offset%29/3
[4] https://www.suse.com/support/kb/doc/?id=000017259
[5] https://docs.vmware.com/en/VMware-vSphere/7.0/com.vmware.vsphere.networking.doc/GUID-FB4F8DB7-B4AC-4442-9B0B-B776F0C7BCCB.html
[6] https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/performance_tuning_guide/network-nic-offloads
[7] https://kb.vmware.com/s/article/2055140
[8] https://www.ibm.com/docs/en/linux-on-z?topic=offload-tcp-segmentation


