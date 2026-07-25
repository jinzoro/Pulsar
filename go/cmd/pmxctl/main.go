// SPDX-License-Identifier: MIT

package main

import (
	"fmt"
	"os"

	"github.com/rs/zerolog"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"

	"github.com/proxmox-kvm-swissknife/internal/config"
	"github.com/proxmox-kvm-swissknife/internal/proxmox"
)

var (
	cfgFile string
	log     zerolog.Logger
	cfg     *config.Config
	client  *proxmox.Client
)

func main() {
	rootCmd := newRootCmd()
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func newRootCmd() *cobra.Command {
	rootCmd := &cobra.Command{
		Use:   "pmxctl",
		Short: "Proxmox VE command-line management tool",
		Long:  `pmxctl provides a comprehensive CLI for managing Proxmox VE clusters, VMs, containers, storage, networking, and more.`,
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			log = zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr}).
				With().
				Timestamp().
				Str("cmd", cmd.CommandPath()).
				Logger()

			level, err := zerolog.ParseLevel(viper.GetString("log-level"))
			if err == nil {
				log = log.Level(level)
			}

			cfg, err = config.Load(cfgFile)
			if err != nil {
				return fmt.Errorf("loading config: %w", err)
			}

			proxmoxCfg := cfg.Proxmox
			if viper.GetString("api-url") != "" {
				proxmoxCfg.APIURL = viper.GetString("api-url")
			}
			if viper.GetString("api-token-id") != "" {
				proxmoxCfg.APITokenID = viper.GetString("api-token-id")
			}
			if viper.GetString("api-token-secret") != "" {
				proxmoxCfg.APITokenSecret = viper.GetString("api-token-secret")
			}

			client, err = proxmox.New(
				proxmoxCfg.APIURL,
				proxmoxCfg.User,
				proxmoxCfg.APITokenID,
				proxmoxCfg.APITokenSecret,
			)
			if err != nil {
				return fmt.Errorf("creating proxmox client: %w", err)
			}
			client.SetTimeout(proxmoxCfg.Timeout)

			return nil
		},
		SilenceUsage: true,
	}

	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default $HOME/.pmxctl.yaml)")
	rootCmd.PersistentFlags().String("api-url", "", "Proxmox API URL")
	rootCmd.PersistentFlags().String("api-token-id", "", "Proxmox API token ID")
	rootCmd.PersistentFlags().String("api-token-secret", "", "Proxmox API token secret")
	rootCmd.PersistentFlags().String("log-level", "info", "log level (trace,debug,info,warn,error,fatal)")

	_ = viper.BindPFlag("api-url", rootCmd.PersistentFlags().Lookup("api-url"))
	_ = viper.BindPFlag("api-token-id", rootCmd.PersistentFlags().Lookup("api-token-id"))
	_ = viper.BindPFlag("api-token-secret", rootCmd.PersistentFlags().Lookup("api-token-secret"))
	_ = viper.BindPFlag("log-level", rootCmd.PersistentFlags().Lookup("log-level"))

	rootCmd.AddCommand(
		newNodeCmd(),
		newVMCmd(),
		newCTCmd(),
		newStorageCmd(),
		newBackupCmd(),
		newClusterCmd(),
		newHACmd(),
		newFirewallCmd(),
		newUserCmd(),
		newSnapshotCmd(),
		newMigrationCmd(),
		newNetworkCmd(),
		newCephCmd(),
		newZFSCmd(),
		newHealthCmd(),
	)

	return rootCmd
}

func newNodeCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "node",
		Short: "Manage Proxmox nodes",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "list",
			Short: "List all nodes",
			RunE: func(cmd *cobra.Command, args []string) error {
				nodes, err := client.ListNodes()
				if err != nil {
					return err
				}
				for _, n := range nodes {
					fmt.Printf("%-15s %-10s %d/%d CPU  %d%% Mem\n",
						n.Node, n.Status, int(n.CPU*100), len(nodes), n.Memory.Used*100/n.Memory.Total)
				}
				return nil
			},
		},
		&cobra.Command{
			Use:   "status [node]",
			Short: "Get node status",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				status, err := client.GetNodeStatus(args[0])
				if err != nil {
					return err
				}
				fmt.Printf("Node: %s\nStatus: %s\nCPU: %.2f%%\nMemory: %d/%d bytes\nUptime: %d seconds\n",
					status.Node, status.Status, status.CPU*100,
					status.Memory.Used, status.Memory.Total, status.Uptime)
				return nil
			},
		},
	)

	return cmd
}

func newVMCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "vm",
		Short: "Manage virtual machines",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "list",
			Short: "List all VMs",
			RunE: func(cmd *cobra.Command, args []string) error {
				vms, err := client.ListVMs()
				if err != nil {
					return err
				}
				fmt.Printf("%-8s %-30s %-10s %-6s %-10s\n", "VMID", "NAME", "STATUS", "CPU", "MEM (MB)")
				for _, vm := range vms {
					fmt.Printf("%-8d %-30s %-10s %-6d %-10d\n",
						vm.VMID, vm.Name, vm.Status, vm.CPUs, vm.MaxMem/1024/1024)
				}
				return nil
			},
		},
		&cobra.Command{
			Use:   "status [vmid]",
			Short: "Get VM status",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				status, err := client.GetVMStatus(args[0])
				if err != nil {
					return err
				}
				fmt.Printf("VMID: %s\nName: %s\nStatus: %s\nCPU: %.2f%%\nMemory: %d/%d bytes\n",
					status.VMID, status.Name, status.Status, status.CPU*100,
					status.Memory, status.MaxMem)
				return nil
			},
		},
		&cobra.Command{
			Use:   "start [vmid]",
			Short: "Start a VM",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				return client.StartVM(args[0])
			},
		},
		&cobra.Command{
			Use:   "stop [vmid]",
			Short: "Stop a VM",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				return client.StopVM(args[0])
			},
		},
		&cobra.Command{
			Use:   "shutdown [vmid]",
			Short: "Gracefully shutdown a VM",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				return client.ShutdownVM(args[0])
			},
		},
		&cobra.Command{
			Use:   "delete [vmid]",
			Short: "Delete a VM",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				return client.DeleteVM(args[0])
			},
		},
		&cobra.Command{
			Use:   "clone [vmid]",
			Short: "Clone a VM",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				newid, _ := cmd.Flags().GetInt("newid")
				name, _ := cmd.Flags().GetString("name")
				full, _ := cmd.Flags().GetBool("full")
				return client.CloneVM(args[0], newid, name, full)
			},
		},
	)

	return cmd
}

func newCTCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "ct",
		Short: "Manage LXC containers",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "list",
			Short: "List all containers",
			RunE: func(cmd *cobra.Command, args []string) error {
				cts, err := client.ListContainers()
				if err != nil {
					return err
				}
				fmt.Printf("%-8s %-30s %-10s\n", "CTID", "NAME", "STATUS")
				for _, ct := range cts {
					fmt.Printf("%-8d %-30s %-10s\n", ct.VMID, ct.Name, ct.Status)
				}
				return nil
			},
		},
		&cobra.Command{
			Use:   "start [ctid]",
			Short: "Start a container",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				return client.StartContainer(args[0])
			},
		},
		&cobra.Command{
			Use:   "stop [ctid]",
			Short: "Stop a container",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				return client.StopContainer(args[0])
			},
		},
		&cobra.Command{
			Use:   "delete [ctid]",
			Short: "Delete a container",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				return client.DeleteContainer(args[0])
			},
		},
	)

	return cmd
}

func newStorageCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "storage",
		Short: "Manage storage",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "list",
			Short: "List storage pools",
			RunE: func(cmd *cobra.Command, args []string) error {
				pools, err := client.ListStorage()
				if err != nil {
					return err
				}
				fmt.Printf("%-20s %-10s %-15s %-10s\n", "NAME", "TYPE", "STATUS", "USAGE")
				for _, p := range pools {
					fmt.Printf("%-20s %-10s %-15s %-10s\n", p.Storage, p.Type, p.Status, p.Content)
				}
				return nil
			},
		},
	)

	return cmd
}

func newBackupCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "backup",
		Short: "Manage backups",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "list [storage]",
			Short: "List backups in a storage",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				backups, err := client.ListBackups(args[0])
				if err != nil {
					return err
				}
				for _, b := range backups {
					fmt.Printf("%-40s %-20s\n", b.Volid, b.Format)
				}
				return nil
			},
		},
	)

	return cmd
}

func newClusterCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "cluster",
		Short: "Manage cluster",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "status",
			Short: "Get cluster status",
			RunE: func(cmd *cobra.Command, args []string) error {
				status, err := client.GetClusterStatus()
				if err != nil {
					return err
				}
				fmt.Printf("Cluster: %s\nType: %s\n", status.Name, status.Type)
				for _, n := range status.Nodes {
					fmt.Printf("  Node: %-15s Status: %s ID: %d\n", n.Name, n.Status, n.ID)
				}
				return nil
			},
		},
		&cobra.Command{
			Use:   "nodes",
			Short: "List cluster nodes",
			RunE: func(cmd *cobra.Command, args []string) error {
				nodes, err := client.GetClusterNodes()
				if err != nil {
					return err
				}
				fmt.Printf("%-15s %-10s %-6s\n", "NAME", "STATUS", "ID")
				for _, n := range nodes {
					fmt.Printf("%-15s %-10s %-6d\n", n.Name, n.Status, n.ID)
				}
				return nil
			},
		},
	)

	return cmd
}

func newHACmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "ha",
		Short: "Manage high availability",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "groups",
			Short: "List HA groups",
			RunE: func(cmd *cobra.Command, args []string) error {
				groups, err := client.ListHAGroups()
				if err != nil {
					return err
				}
				for _, g := range groups {
					fmt.Printf("%-20s\n", g.Group)
				}
				return nil
			},
		},
		&cobra.Command{
			Use:   "resources",
			Short: "List HA resources",
			RunE: func(cmd *cobra.Command, args []string) error {
				resources, err := client.ListHAResources()
				if err != nil {
					return err
				}
				fmt.Printf("%-8s %-10s %-20s %-10s\n", "SID", "TYPE", "GROUP", "STATE")
				for _, r := range resources {
					fmt.Printf("%-8s %-10s %-20s %-10s\n", r.SID, r.Type, r.Group, r.State)
				}
				return nil
			},
		},
	)

	return cmd
}

func newFirewallCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "firewall",
		Short: "Manage firewall",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "rules",
			Short: "List firewall rules",
			RunE: func(cmd *cobra.Command, args []string) error {
				rules, err := client.ListFirewallRules()
				if err != nil {
					return err
				}
				fmt.Printf("%-6s %-10s %-10s %-20s %-20s\n", "POS", "ACTION", "PROTO", "SOURCE", "DEST")
				for _, r := range rules {
					fmt.Printf("%-6d %-10s %-10s %-20s %-20s\n",
						r.Pos, r.Action, r.Proto, r.Source, r.Dest)
				}
				return nil
			},
		},
	)

	return cmd
}

func newUserCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "user",
		Short: "Manage users",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "list",
			Short: "List users",
			RunE: func(cmd *cobra.Command, args []string) error {
				users, err := client.ListUsers()
				if err != nil {
					return err
				}
				fmt.Printf("%-30s %-20s %-10s\n", "USERID", "EMAIL", "ENABLED")
				for _, u := range users {
					fmt.Printf("%-30s %-20s %-10v\n", u.UserID, u.Email, u.Enable)
				}
				return nil
			},
		},
	)

	return cmd
}

func newSnapshotCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "snapshot",
		Short: "Manage VM snapshots",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "list [vmid]",
			Short: "List VM snapshots",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				snaps, err := client.ListSnapshots(args[0])
				if err != nil {
					return err
				}
				fmt.Printf("%-10s %-25s %-30s\n", "SNAP", "NAME", "TIME")
				for _, s := range snaps {
					fmt.Printf("%-10d %-25s %-30s\n", s.ID, s.Name, s.Time)
				}
				return nil
			},
		},
		&cobra.Command{
			Use:   "create [vmid] [name]",
			Short: "Create a snapshot",
			Args:  cobra.ExactArgs(2),
			RunE: func(cmd *cobra.Command, args []string) error {
				desc, _ := cmd.Flags().GetString("description")
				return client.CreateSnapshot(args[0], args[1], desc)
			},
		},
		&cobra.Command{
			Use:   "delete [vmid] [snapname]",
			Short: "Delete a snapshot",
			Args:  cobra.ExactArgs(2),
			RunE: func(cmd *cobra.Command, args []string) error {
				return client.DeleteSnapshot(args[0], args[1])
			},
		},
		&cobra.Command{
			Use:   "rollback [vmid] [snapname]",
			Short: "Rollback to a snapshot",
			Args:  cobra.ExactArgs(2),
			RunE: func(cmd *cobra.Command, args []string) error {
				return client.RollbackSnapshot(args[0], args[1])
			},
		},
	)

	return cmd
}

func newMigrationCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "migrate",
		Short: "Migrate VMs/containers",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "vm [vmid] [target]",
			Short: "Migrate a VM",
			Args:  cobra.ExactArgs(2),
			RunE: func(cmd *cobra.Command, args []string) error {
			online, _ := cmd.Flags().GetBool("online")
			return client.MigrateVM(args[0], args[1], online)
		},
		},
	)

	return cmd
}

func newNetworkCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "network",
		Short: "Manage networking",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "list [node]",
			Short: "List network interfaces",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				ifaces, err := client.ListInterfaces(args[0])
				if err != nil {
					return err
				}
				fmt.Printf("%-20s %-10s %-20s %-10s\n", "NAME", "TYPE", "ADDRESS", "STATUS")
				for _, iface := range ifaces {
					fmt.Printf("%-20s %-10s %-20s %-10s\n",
						iface.Name, iface.Type, iface.Address, iface.Status)
				}
				return nil
			},
		},
	)

	return cmd
}

func newCephCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "ceph",
		Short: "Manage Ceph storage",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "status [node]",
			Short: "Get Ceph status",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				fmt.Printf("Ceph status for node: %s\n", args[0])
				return nil
			},
		},
	)

	return cmd
}

func newZFSCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "zfs",
		Short: "Manage ZFS storage",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "list [node]",
			Short: "List ZFS pools",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				fmt.Printf("ZFS pools for node: %s\n", args[0])
				return nil
			},
		},
	)

	return cmd
}

func newHealthCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "health",
		Short: "Cluster health check",
		RunE: func(cmd *cobra.Command, args []string) error {
			nodes, err := client.ListNodes()
			if err != nil {
				return err
			}
			allHealthy := true
			for _, n := range nodes {
				healthy := n.Status == "online"
				status := "HEALTHY"
				if !healthy {
					status = "UNHEALTHY"
					allHealthy = false
				}
				fmt.Printf("%-15s %s\n", n.Node, status)
			}
			if !allHealthy {
				return fmt.Errorf("cluster is unhealthy")
			}
			fmt.Println("\nAll nodes healthy.")
			return nil
		},
	}
}
