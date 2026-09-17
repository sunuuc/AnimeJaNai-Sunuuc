-- Native, in-process Windows measurements. Called only while the performance panel is open.
-- No PowerShell/WMI/nvidia-smi loop and no background monitoring process.
local M={}
local ok,ffi=pcall(require,'ffi')
if not ok or ffi.os~='Windows' then return M end
local declared=pcall(ffi.cdef,[[
typedef struct { unsigned long lo, hi; } PLAYER_UI_FILETIME;
typedef struct { unsigned long cb, PageFaultCount; size_t PeakWorkingSetSize, WorkingSetSize,
 QuotaPeakPagedPoolUsage, QuotaPagedPoolUsage, QuotaPeakNonPagedPoolUsage,
 QuotaNonPagedPoolUsage, PagefileUsage, PeakPagefileUsage, PrivateUsage; } PLAYER_UI_PMC;
void* __stdcall GetCurrentProcess(void);
int __stdcall GetProcessTimes(void*, PLAYER_UI_FILETIME*, PLAYER_UI_FILETIME*, PLAYER_UI_FILETIME*, PLAYER_UI_FILETIME*);
unsigned long __stdcall GetActiveProcessorCount(unsigned short);
int __stdcall K32GetProcessMemoryInfo(void*, PLAYER_UI_PMC*, unsigned long);
]])
if not declared then return M end
local k=ffi.load('kernel32')
local last_time,last_cpu
function M.reset() last_time,last_cpu=nil,nil end
function M.read(now)
    local result={}
    local success=pcall(function()
        local handle=k.GetCurrentProcess()
        local t=ffi.new('PLAYER_UI_FILETIME[4]')
        if k.GetProcessTimes(handle,t,t+1,t+2,t+3)~=0 then
            local cpu=(tonumber(t[2].hi)*4294967296+tonumber(t[2].lo)+tonumber(t[3].hi)*4294967296+tonumber(t[3].lo))/1e7
            local cores=math.max(1,tonumber(k.GetActiveProcessorCount(65535)))
            if last_time and now>last_time and cpu>=last_cpu then result.cpu=math.min(100,100*(cpu-last_cpu)/((now-last_time)*cores)) end
            last_time,last_cpu=now,cpu
        end
        local m=ffi.new('PLAYER_UI_PMC[1]');m[0].cb=ffi.sizeof(m[0])
        if k.K32GetProcessMemoryInfo(handle,m,ffi.sizeof(m[0]))~=0 then result.memory=tonumber(m[0].WorkingSetSize) end
    end)
    return success and result or {}
end
return M
