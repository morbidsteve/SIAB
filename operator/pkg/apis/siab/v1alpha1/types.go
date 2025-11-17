package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

// SIABApplication is the Schema for the siabapplications API
type SIABApplication struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   SIABApplicationSpec   `json:"spec,omitempty"`
	Status SIABApplicationStatus `json:"status,omitempty"`
}

// SIABApplicationSpec defines the desired state of SIABApplication
type SIABApplicationSpec struct {
	Image         string                    `json:"image"`
	Replicas      int32                     `json:"replicas,omitempty"`
	Port          int32                     `json:"port,omitempty"`
	Env           []corev1.EnvVar           `json:"env,omitempty"`
	Resources     *ResourceRequirements     `json:"resources,omitempty"`
	Security      *SecurityConfig           `json:"security,omitempty"`
	Auth          *AuthConfig               `json:"auth,omitempty"`
	Storage       *StorageConfig            `json:"storage,omitempty"`
	ObjectStorage *ObjectStorageConfig      `json:"objectStorage,omitempty"`
	Ingress       *IngressConfig            `json:"ingress,omitempty"`
	Networking    *NetworkingConfig         `json:"networking,omitempty"`
	HealthCheck   *HealthCheckConfig        `json:"healthCheck,omitempty"`
	Scaling       *ScalingConfig            `json:"scaling,omitempty"`
}

type ResourceRequirements struct {
	Requests ResourceList `json:"requests,omitempty"`
	Limits   ResourceList `json:"limits,omitempty"`
}

type ResourceList struct {
	CPU    string `json:"cpu,omitempty"`
	Memory string `json:"memory,omitempty"`
}

type SecurityConfig struct {
	ScanOnDeploy             bool   `json:"scanOnDeploy,omitempty"`
	BlockCriticalVulns       bool   `json:"blockCriticalVulns,omitempty"`
	BlockHighVulns           bool   `json:"blockHighVulns,omitempty"`
	RequireImageSigning      bool   `json:"requireImageSigning,omitempty"`
	RunAsNonRoot             bool   `json:"runAsNonRoot,omitempty"`
	ReadOnlyRootFilesystem   bool   `json:"readOnlyRootFilesystem,omitempty"`
	AllowPrivilegeEscalation bool   `json:"allowPrivilegeEscalation,omitempty"`
	SeccompProfile           string `json:"seccompProfile,omitempty"`
}

type AuthConfig struct {
	Enabled        bool     `json:"enabled,omitempty"`
	RequiredRoles  []string `json:"requiredRoles,omitempty"`
	RequiredGroups []string `json:"requiredGroups,omitempty"`
	PublicPaths    []string `json:"publicPaths,omitempty"`
}

type StorageConfig struct {
	Enabled      bool   `json:"enabled,omitempty"`
	Size         string `json:"size,omitempty"`
	StorageClass string `json:"storageClass,omitempty"`
	MountPath    string `json:"mountPath,omitempty"`
	AccessMode   string `json:"accessMode,omitempty"`
}

type ObjectStorageConfig struct {
	Enabled           bool   `json:"enabled,omitempty"`
	BucketName        string `json:"bucketName,omitempty"`
	QuotaSize         string `json:"quotaSize,omitempty"`
	InjectCredentials bool   `json:"injectCredentials,omitempty"`
}

type IngressConfig struct {
	Enabled   bool              `json:"enabled,omitempty"`
	Hostname  string            `json:"hostname,omitempty"`
	TLS       bool              `json:"tls,omitempty"`
	Paths     []string          `json:"paths,omitempty"`
	RateLimit *RateLimitConfig  `json:"rateLimit,omitempty"`
	CORS      *CORSConfig       `json:"cors,omitempty"`
}

type RateLimitConfig struct {
	Enabled           bool  `json:"enabled,omitempty"`
	RequestsPerSecond int32 `json:"requestsPerSecond,omitempty"`
	BurstSize         int32 `json:"burstSize,omitempty"`
}

type CORSConfig struct {
	Enabled      bool     `json:"enabled,omitempty"`
	AllowOrigins []string `json:"allowOrigins,omitempty"`
	AllowMethods []string `json:"allowMethods,omitempty"`
	AllowHeaders []string `json:"allowHeaders,omitempty"`
}

type NetworkingConfig struct {
	AllowInternetEgress bool     `json:"allowInternetEgress,omitempty"`
	AllowedEgressPorts  []int32  `json:"allowedEgressPorts,omitempty"`
	AllowedEgressCIDRs  []string `json:"allowedEgressCIDRs,omitempty"`
	AllowIngressFrom    []string `json:"allowIngressFrom,omitempty"`
}

type HealthCheckConfig struct {
	Enabled             bool   `json:"enabled,omitempty"`
	Path                string `json:"path,omitempty"`
	Port                int32  `json:"port,omitempty"`
	InitialDelaySeconds int32  `json:"initialDelaySeconds,omitempty"`
	PeriodSeconds       int32  `json:"periodSeconds,omitempty"`
	TimeoutSeconds      int32  `json:"timeoutSeconds,omitempty"`
	FailureThreshold    int32  `json:"failureThreshold,omitempty"`
}

type ScalingConfig struct {
	Enabled                 bool  `json:"enabled,omitempty"`
	MinReplicas             int32 `json:"minReplicas,omitempty"`
	MaxReplicas             int32 `json:"maxReplicas,omitempty"`
	TargetCPUUtilization    int32 `json:"targetCPUUtilization,omitempty"`
	TargetMemoryUtilization int32 `json:"targetMemoryUtilization,omitempty"`
}

// SIABApplicationStatus defines the observed state of SIABApplication
type SIABApplicationStatus struct {
	Phase                string                     `json:"phase,omitempty"`
	Conditions           []metav1.Condition         `json:"conditions,omitempty"`
	AvailableReplicas    int32                      `json:"availableReplicas,omitempty"`
	VulnerabilitySummary *VulnerabilitySummary      `json:"vulnerabilitySummary,omitempty"`
	Endpoints            *Endpoints                 `json:"endpoints,omitempty"`
}

type VulnerabilitySummary struct {
	Critical     int32       `json:"critical,omitempty"`
	High         int32       `json:"high,omitempty"`
	Medium       int32       `json:"medium,omitempty"`
	Low          int32       `json:"low,omitempty"`
	LastScanTime metav1.Time `json:"lastScanTime,omitempty"`
}

type Endpoints struct {
	Internal string `json:"internal,omitempty"`
	External string `json:"external,omitempty"`
}

// +kubebuilder:object:root=true

// SIABApplicationList contains a list of SIABApplication
type SIABApplicationList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []SIABApplication `json:"items"`
}

func init() {
	SchemeBuilder.Register(&SIABApplication{}, &SIABApplicationList{})
}
