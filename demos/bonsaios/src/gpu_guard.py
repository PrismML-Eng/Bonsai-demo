"""Resolve CUDA-visible UUID, then inspect only that GPU before model startup."""
import ctypes, json, os, subprocess, time, uuid

def check_assigned_gpu(log):
    cuda=ctypes.CDLL('libcuda.so.1')
    def checked(name,*args):
        code=getattr(cuda,name)(*args)
        if code:raise RuntimeError(f'{name} failed: {code}')
    checked('cuInit',0)
    count=ctypes.c_int();checked('cuDeviceGetCount',ctypes.byref(count))
    if count.value!=1:raise RuntimeError(f'Expected one allocated CUDA-visible GPU, got {count.value}; refusing startup')
    device=ctypes.c_int();checked('cuDeviceGet',ctypes.byref(device),0)
    raw=(ctypes.c_ubyte*16)();checked('cuDeviceGetUuid',ctypes.byref(raw),device)
    gpu='GPU-'+str(uuid.UUID(bytes=bytes(raw)))
    def processes():
        r=subprocess.run(['nvidia-smi','-i',gpu,'--query-compute-apps=gpu_uuid,pid,process_name,used_memory','--format=csv,noheader'],text=True,capture_output=True,check=True)
        return [line.strip() for line in r.stdout.splitlines() if line.strip()]
    first=processes();time.sleep(1);second=processes()
    result={'uuid':gpu,'cuda_visible_devices':os.environ.get('CUDA_VISIBLE_DEVICES'),'step_gpus':os.environ.get('SLURM_STEP_GPUS'),'job_gpus':os.environ.get('SLURM_JOB_GPUS'),'pid':os.getpid(),'initial_compute_processes':first,'recheck_compute_processes':second,'empty':not first and not second}
    (log/'gpu-guard.json').write_text(json.dumps(result,indent=2)+'\n')
    if not result['empty']:raise RuntimeError('Assigned GPU has existing compute processes; refusing startup')
    return gpu
