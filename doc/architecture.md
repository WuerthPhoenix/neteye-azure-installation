# Architecture Diagrams
The architecture of Neteye on Azure is designed to leverage the cloud platform's capabilities and therefore may differ from traditional on-premises deployments.

The following diagrams illustrate the key components and their interactions within the Neteye deployment on Azure.
## Incoming Traffic
All the incoming traffic from internet (directed to the webui) is routed through an Application Gateway which secure and
forwards the traffic to a Load Balancer (External LB) that distributes the requests to the Neteye nodes based on their health status.

The Load Balancer uses the same Cluster IP as the Neteye cluster and relies on pcs health probes 
to determine which node has currently assigned the Cluster IP.
```mermaid
flowchart TD
    Internet@{shape: cloud} -->|Public ip| gateway(Application Gateway)
    gateway -->|Neteye Cluster IP| ExternalLB{External LB}
    
    ExternalLB --> n0["neteye 0<br><font color='green'>clusterIP probe active</font>"]
    ExternalLB --> n1["neteye 1<br><font color='grey'>clusterIP probe inactive</font>"]
    ExternalLB --> n2["neteye 2<br><font color='grey'>clusterIP probe inactive</font>"]

linkStyle default stroke:grey,stroke-width:1px,labelBackground:,stroke-dasharray: 4 3;
linkStyle 0 stroke:green,stroke-width:3px,stroke-dasharray: 0;
linkStyle 1 stroke:green,stroke-width:3px,stroke-dasharray: 0;
linkStyle 2 stroke:green,stroke-width:3px,stroke-dasharray: 0;
```

> [!NOTE]
> No public IP is therefore assigned directly to the Neteye nodes. SSH access is only possible via a Bastion Host or via a
> VPN connection to the virtual network.


## Internal Traffic Towards Cluster IP
If a Neteye node needs to communicate with the Cluster IP (e.g. for internal API calls), all requests are routed back to
the External Load Balancer that forwards them to the node currently owning the Cluster IP.
```mermaid
flowchart TD
    Internet@{shape: cloud} -->|Public ip| gateway(Application Gateway)
    gateway -->|Neteye Cluster IP| ExternalLB{External LB}
    
    ExternalLB --> n0["neteye 0<br><font color='green'>clusterIP probe active</font>"]
    ExternalLB --> n1["neteye 1<br><font color='grey'>clusterIP probe inactive</font>"]
    ExternalLB --> n2["neteye 2<br><font color='grey'>clusterIP probe inactive</font>"]
    n2 --> |Internal request towards cluster ip| ExternalLB

linkStyle default stroke:grey,stroke-width:1px,stroke-dasharray: 4 3;
linkStyle 5 stroke:green,stroke-width:3px,stroke-dasharray: 0;
linkStyle 2 stroke:green,stroke-width:3px,stroke-dasharray: 0;
```

## Traffic towards Internet
Otherwise, all outgoing traffic from the Neteye nodes towards external networks is routed through a NAT Gateway. 

This ensures that the outgoing traffic uses a consistent public IP address (useful for ip filtering).
```mermaid
flowchart TD
    gateway(NAT Gateway) -->|Public ip| Internet@{shape: cloud}
    n0 --> gateway
    n1 --> gateway
    n2 --> gateway

linkStyle default stroke:green,stroke-width:3px;
```

## Traffic between Neteye Nodes
All traffic directed towards a pacemaker virtual IP is routed through an Internal Load Balancer, which detects via pcs health probes
which node currently owns the virtual IP and forwards the traffic accordingly.
```mermaid
flowchart TD
    n0["neteye0<br><font color='green'>PCS service probe active</font>"] --> internalLB{Internal LB}
    n1["neteye1<br><font color='grey'>PCS service probe inactive</font>"] --> |Traffic towards PCS service IP| internalLB
    n2["neteye2<br><font color='grey'>PCS service probe inactive</font>"] --> internalLB
    internalLB --> n0

linkStyle default stroke:grey,stroke-width:1px,labelBackground:,stroke-dasharray: 4 3;
linkStyle 1 stroke:green,stroke-width:3px,stroke-dasharray: 0;
linkStyle 3 stroke:green,stroke-width:3px,stroke-dasharray: 0;
```

All the remaining traffic between the Neteye nodes is routed directly without any load balancer.