#!/bin/bash

echo "Checking GPU usage across all nodes..."

# Loop through nodes that advertise GPU resources
for node in $(oc get nodes -o jsonpath='{.items[*].metadata.name}'); do
  gpu_count=$(oc get node "$node" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null)

  if [[ -n "$gpu_count" && "$gpu_count" != "<nil>" ]]; then
    echo "-------------------------------------------------"
    echo "Node: $node"
    echo "GPUs Allocatable: $gpu_count"
    
    # Show which pods on this node are using GPUs
    oc get pods -A --field-selector spec.nodeName=$node \
      -o custom-columns=NAMESPACE:.metadata.namespace,POD:.metadata.name,GPUS:.spec.containers[*].resources.limits.'nvidia\.com/gpu' \
      | grep -v "<none>" || echo "No pods requesting GPUs"

    # Optional: check runtime GPU usage with nvidia-smi inside dcgm-exporter pod (if GPU Operator is installed)
    dcgm_pod=$(oc get pod -n nvidia-gpu-operator -o name | grep dcgm-exporter | head -n1)
    if [[ -n "$dcgm_pod" ]]; then
      echo "Running nvidia-smi for node $node..."
      oc rsh -n nvidia-gpu-operator "$dcgm_pod" nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null | grep -v '^$' || echo "No active GPU processes"
    fi
  fi
done

