package controller

import (
	"context"
	"fmt"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	siabv1alpha1 "github.com/morbidsteve/siab-operator/pkg/apis/siab/v1alpha1"
)

// SIABApplicationReconciler reconciles a SIABApplication object
type SIABApplicationReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=siab.io,resources=siabapplications,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=siab.io,resources=siabapplications/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=siab.io,resources=siabapplications/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=services,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=persistentvolumeclaims,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=networking.k8s.io,resources=networkpolicies,verbs=get;list;watch;create;update;patch;delete

func (r *SIABApplicationReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	// Fetch the SIABApplication instance
	app := &siabv1alpha1.SIABApplication{}
	err := r.Get(ctx, req.NamespacedName, app)
	if err != nil {
		if errors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// Set default values
	r.setDefaults(app)

	// Update status to Deploying
	app.Status.Phase = "Deploying"
	if err := r.Status().Update(ctx, app); err != nil {
		logger.Error(err, "Failed to update status")
	}

	// Create or update the Deployment
	deployment := r.deploymentForApp(app)
	if err := r.createOrUpdate(ctx, deployment, app); err != nil {
		app.Status.Phase = "Failed"
		r.Status().Update(ctx, app)
		return ctrl.Result{}, err
	}

	// Create or update the Service
	service := r.serviceForApp(app)
	if err := r.createOrUpdate(ctx, service, app); err != nil {
		app.Status.Phase = "Failed"
		r.Status().Update(ctx, app)
		return ctrl.Result{}, err
	}

	// Create Network Policy
	netpol := r.networkPolicyForApp(app)
	if err := r.createOrUpdate(ctx, netpol, app); err != nil {
		logger.Error(err, "Failed to create NetworkPolicy")
	}

	// Create PVC if storage is enabled
	if app.Spec.Storage != nil && app.Spec.Storage.Enabled {
		pvc := r.pvcForApp(app)
		if err := r.createOrUpdate(ctx, pvc, app); err != nil {
			logger.Error(err, "Failed to create PVC")
		}
	}

	// Update status
	app.Status.Phase = "Running"
	app.Status.Endpoints = &siabv1alpha1.Endpoints{
		Internal: fmt.Sprintf("%s.%s.svc.cluster.local:%d", app.Name, app.Namespace, app.Spec.Port),
	}
	if app.Spec.Ingress != nil && app.Spec.Ingress.Enabled {
		app.Status.Endpoints.External = fmt.Sprintf("https://%s", app.Spec.Ingress.Hostname)
	}

	if err := r.Status().Update(ctx, app); err != nil {
		logger.Error(err, "Failed to update status")
		return ctrl.Result{}, err
	}

	return ctrl.Result{}, nil
}

func (r *SIABApplicationReconciler) setDefaults(app *siabv1alpha1.SIABApplication) {
	if app.Spec.Replicas == 0 {
		app.Spec.Replicas = 1
	}
	if app.Spec.Port == 0 {
		app.Spec.Port = 8080
	}
	if app.Spec.Security == nil {
		app.Spec.Security = &siabv1alpha1.SecurityConfig{
			ScanOnDeploy:             true,
			BlockCriticalVulns:       true,
			RunAsNonRoot:             true,
			ReadOnlyRootFilesystem:   true,
			AllowPrivilegeEscalation: false,
			SeccompProfile:           "RuntimeDefault",
		}
	}
	if app.Spec.Resources == nil {
		app.Spec.Resources = &siabv1alpha1.ResourceRequirements{
			Requests: siabv1alpha1.ResourceList{
				CPU:    "100m",
				Memory: "128Mi",
			},
			Limits: siabv1alpha1.ResourceList{
				CPU:    "500m",
				Memory: "512Mi",
			},
		}
	}
	if app.Spec.HealthCheck == nil {
		app.Spec.HealthCheck = &siabv1alpha1.HealthCheckConfig{
			Enabled:             true,
			Path:                "/health",
			Port:                app.Spec.Port,
			InitialDelaySeconds: 30,
			PeriodSeconds:       10,
			TimeoutSeconds:      5,
			FailureThreshold:    3,
		}
	}
}

func (r *SIABApplicationReconciler) deploymentForApp(app *siabv1alpha1.SIABApplication) *appsv1.Deployment {
	labels := map[string]string{
		"app":                          app.Name,
		"siab.io/application":          app.Name,
		"app.kubernetes.io/managed-by": "siab-operator",
	}

	// Security context
	runAsNonRoot := app.Spec.Security.RunAsNonRoot
	readOnlyRootFilesystem := app.Spec.Security.ReadOnlyRootFilesystem
	allowPrivilegeEscalation := app.Spec.Security.AllowPrivilegeEscalation
	var runAsUser int64 = 1000

	deployment := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      app.Name,
			Namespace: app.Namespace,
			Labels:    labels,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: &app.Spec.Replicas,
			Selector: &metav1.LabelSelector{
				MatchLabels: labels,
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: labels,
					Annotations: map[string]string{
						"sidecar.istio.io/inject": "true",
					},
				},
				Spec: corev1.PodSpec{
					SecurityContext: &corev1.PodSecurityContext{
						RunAsNonRoot: &runAsNonRoot,
						RunAsUser:    &runAsUser,
						SeccompProfile: &corev1.SeccompProfile{
							Type: corev1.SeccompProfileTypeRuntimeDefault,
						},
					},
					Containers: []corev1.Container{
						{
							Name:  "app",
							Image: app.Spec.Image,
							Ports: []corev1.ContainerPort{
								{
									ContainerPort: app.Spec.Port,
									Protocol:      corev1.ProtocolTCP,
								},
							},
							Env: app.Spec.Env,
							Resources: corev1.ResourceRequirements{
								Requests: corev1.ResourceList{
									corev1.ResourceCPU:    resource.MustParse(app.Spec.Resources.Requests.CPU),
									corev1.ResourceMemory: resource.MustParse(app.Spec.Resources.Requests.Memory),
								},
								Limits: corev1.ResourceList{
									corev1.ResourceCPU:    resource.MustParse(app.Spec.Resources.Limits.CPU),
									corev1.ResourceMemory: resource.MustParse(app.Spec.Resources.Limits.Memory),
								},
							},
							SecurityContext: &corev1.SecurityContext{
								RunAsNonRoot:             &runAsNonRoot,
								ReadOnlyRootFilesystem:   &readOnlyRootFilesystem,
								AllowPrivilegeEscalation: &allowPrivilegeEscalation,
								Capabilities: &corev1.Capabilities{
									Drop: []corev1.Capability{"ALL"},
								},
							},
						},
					},
				},
			},
		},
	}

	// Add health checks if enabled
	if app.Spec.HealthCheck != nil && app.Spec.HealthCheck.Enabled {
		port := app.Spec.HealthCheck.Port
		if port == 0 {
			port = app.Spec.Port
		}
		deployment.Spec.Template.Spec.Containers[0].LivenessProbe = &corev1.Probe{
			ProbeHandler: corev1.ProbeHandler{
				HTTPGet: &corev1.HTTPGetAction{
					Path: app.Spec.HealthCheck.Path,
					Port: intstr.FromInt(int(port)),
				},
			},
			InitialDelaySeconds: app.Spec.HealthCheck.InitialDelaySeconds,
			PeriodSeconds:       app.Spec.HealthCheck.PeriodSeconds,
			TimeoutSeconds:      app.Spec.HealthCheck.TimeoutSeconds,
			FailureThreshold:    app.Spec.HealthCheck.FailureThreshold,
		}
		deployment.Spec.Template.Spec.Containers[0].ReadinessProbe = &corev1.Probe{
			ProbeHandler: corev1.ProbeHandler{
				HTTPGet: &corev1.HTTPGetAction{
					Path: app.Spec.HealthCheck.Path,
					Port: intstr.FromInt(int(port)),
				},
			},
			InitialDelaySeconds: 5,
			PeriodSeconds:       app.Spec.HealthCheck.PeriodSeconds,
			TimeoutSeconds:      app.Spec.HealthCheck.TimeoutSeconds,
			FailureThreshold:    app.Spec.HealthCheck.FailureThreshold,
		}
	}

	// Add volume mounts if storage is enabled
	if app.Spec.Storage != nil && app.Spec.Storage.Enabled {
		deployment.Spec.Template.Spec.Volumes = []corev1.Volume{
			{
				Name: "data",
				VolumeSource: corev1.VolumeSource{
					PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
						ClaimName: app.Name + "-pvc",
					},
				},
			},
		}
		deployment.Spec.Template.Spec.Containers[0].VolumeMounts = []corev1.VolumeMount{
			{
				Name:      "data",
				MountPath: app.Spec.Storage.MountPath,
			},
		}
	}

	return deployment
}

func (r *SIABApplicationReconciler) serviceForApp(app *siabv1alpha1.SIABApplication) *corev1.Service {
	labels := map[string]string{
		"app":                 app.Name,
		"siab.io/application": app.Name,
	}

	return &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      app.Name,
			Namespace: app.Namespace,
			Labels:    labels,
		},
		Spec: corev1.ServiceSpec{
			Selector: labels,
			Ports: []corev1.ServicePort{
				{
					Port:       app.Spec.Port,
					TargetPort: intstr.FromInt(int(app.Spec.Port)),
					Protocol:   corev1.ProtocolTCP,
				},
			},
		},
	}
}

func (r *SIABApplicationReconciler) pvcForApp(app *siabv1alpha1.SIABApplication) *corev1.PersistentVolumeClaim {
	storageClass := app.Spec.Storage.StorageClass
	if storageClass == "" {
		storageClass = "local-path"
	}

	accessMode := corev1.ReadWriteOnce
	if app.Spec.Storage.AccessMode == "ReadWriteMany" {
		accessMode = corev1.ReadWriteMany
	} else if app.Spec.Storage.AccessMode == "ReadOnlyMany" {
		accessMode = corev1.ReadOnlyMany
	}

	return &corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{
			Name:      app.Name + "-pvc",
			Namespace: app.Namespace,
		},
		Spec: corev1.PersistentVolumeClaimSpec{
			AccessModes: []corev1.PersistentVolumeAccessMode{accessMode},
			Resources: corev1.ResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceStorage: resource.MustParse(app.Spec.Storage.Size),
				},
			},
			StorageClassName: &storageClass,
		},
	}
}

func (r *SIABApplicationReconciler) networkPolicyForApp(app *siabv1alpha1.SIABApplication) *networkingv1.NetworkPolicy {
	labels := map[string]string{
		"app":                 app.Name,
		"siab.io/application": app.Name,
	}

	// Default: deny all ingress except from Istio
	ingressRules := []networkingv1.NetworkPolicyIngressRule{
		{
			From: []networkingv1.NetworkPolicyPeer{
				{
					NamespaceSelector: &metav1.LabelSelector{
						MatchLabels: map[string]string{
							"kubernetes.io/metadata.name": "istio-system",
						},
					},
				},
			},
		},
	}

	// Add allowed namespaces
	if app.Spec.Networking != nil && len(app.Spec.Networking.AllowIngressFrom) > 0 {
		for _, ns := range app.Spec.Networking.AllowIngressFrom {
			ingressRules = append(ingressRules, networkingv1.NetworkPolicyIngressRule{
				From: []networkingv1.NetworkPolicyPeer{
					{
						NamespaceSelector: &metav1.LabelSelector{
							MatchLabels: map[string]string{
								"kubernetes.io/metadata.name": ns,
							},
						},
					},
				},
			})
		}
	}

	// Egress rules
	egressRules := []networkingv1.NetworkPolicyEgressRule{
		// Allow DNS
		{
			Ports: []networkingv1.NetworkPolicyPort{
				{
					Protocol: func() *corev1.Protocol { p := corev1.ProtocolUDP; return &p }(),
					Port:     &intstr.IntOrString{Type: intstr.Int, IntVal: 53},
				},
			},
		},
		// Allow to Istio
		{
			To: []networkingv1.NetworkPolicyPeer{
				{
					NamespaceSelector: &metav1.LabelSelector{
						MatchLabels: map[string]string{
							"kubernetes.io/metadata.name": "istio-system",
						},
					},
				},
			},
		},
	}

	return &networkingv1.NetworkPolicy{
		ObjectMeta: metav1.ObjectMeta{
			Name:      app.Name + "-netpol",
			Namespace: app.Namespace,
		},
		Spec: networkingv1.NetworkPolicySpec{
			PodSelector: metav1.LabelSelector{
				MatchLabels: labels,
			},
			PolicyTypes: []networkingv1.PolicyType{
				networkingv1.PolicyTypeIngress,
				networkingv1.PolicyTypeEgress,
			},
			Ingress: ingressRules,
			Egress:  egressRules,
		},
	}
}

func (r *SIABApplicationReconciler) createOrUpdate(ctx context.Context, obj client.Object, app *siabv1alpha1.SIABApplication) error {
	logger := log.FromContext(ctx)

	// Set owner reference
	if err := ctrl.SetControllerReference(app, obj, r.Scheme); err != nil {
		return err
	}

	// Try to get existing object
	existing := obj.DeepCopyObject().(client.Object)
	err := r.Get(ctx, types.NamespacedName{Name: obj.GetName(), Namespace: obj.GetNamespace()}, existing)
	if err != nil {
		if errors.IsNotFound(err) {
			// Create
			logger.Info("Creating resource", "type", obj.GetObjectKind().GroupVersionKind().Kind, "name", obj.GetName())
			return r.Create(ctx, obj)
		}
		return err
	}

	// Update
	obj.SetResourceVersion(existing.GetResourceVersion())
	logger.Info("Updating resource", "type", obj.GetObjectKind().GroupVersionKind().Kind, "name", obj.GetName())
	return r.Update(ctx, obj)
}

func (r *SIABApplicationReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&siabv1alpha1.SIABApplication{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.Service{}).
		Complete(r)
}
