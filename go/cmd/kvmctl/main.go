// SPDX-License-Identifier: MIT

package main

import (
	"fmt"
	"os"

	"github.com/rs/zerolog"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"

	"github.com/proxmox-kvm-swissknife/internal/config"
	"github.com/proxmox-kvm-swissknife/internal/kvm"
)

var (
	cfgFile string
	log     zerolog.Logger
	cfg     *config.Config
	libvirt *kvm.LibvirtClient
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
		Use:   "kvmctl",
		Short: "KVM/QEMU virtual machine management tool",
		Long:  `kvmctl provides CLI management for local KVM/QEMU virtual machines via libvirt and QMP.`,
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

			uri := cfg.KVM.LibvirtURI
			if viper.GetString("uri") != "" {
				uri = viper.GetString("uri")
			}

			libvirt, err = kvm.NewLibvirtClient(uri)
			if err != nil {
				return fmt.Errorf("connecting to libvirt: %w", err)
			}

			return nil
		},
		SilenceUsage: true,
	}

	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default $HOME/.kvmctl.yaml)")
	rootCmd.PersistentFlags().String("uri", "", "libvirt connection URI")
	rootCmd.PersistentFlags().String("log-level", "info", "log level (trace,debug,info,warn,error,fatal)")

	_ = viper.BindPFlag("uri", rootCmd.PersistentFlags().Lookup("uri"))
	_ = viper.BindPFlag("log-level", rootCmd.PersistentFlags().Lookup("log-level"))

	rootCmd.AddCommand(
		newVMCmd(),
		newDiskCmd(),
		newNetCmd(),
		newSnapshotCmd(),
		newBackupCmd(),
		newPassthroughCmd(),
		newCloudInitCmd(),
		newHealthCmd(),
	)

	return rootCmd
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
				domains, err := libvirt.ListDomains()
				if err != nil {
					return err
				}
				fmt.Printf("%-10s %-30s %-15s %-10s\n", "ID", "NAME", "STATE", "MEMORY (MB)")
				for _, d := range domains {
					fmt.Printf("%-10d %-30s %-15s %-10d\n", d.ID, d.Name, d.State, d.Memory/1024)
				}
				return nil
			},
		},
		&cobra.Command{
			Use:   "start [name|id]",
			Short: "Start a VM",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				domain, err := libvirt.GetDomain(args[0])
				if err != nil {
					return err
				}
				return domain.Start()
			},
		},
		&cobra.Command{
			Use:   "stop [name|id]",
			Short: "Stop a VM",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				force, _ := cmd.Flags().GetBool("force")
				domain, err := libvirt.GetDomain(args[0])
				if err != nil {
					return err
				}
				if force {
					return domain.Destroy()
				}
				return domain.Stop()
			},
		},
		&cobra.Command{
			Use:   "shutdown [name|id]",
			Short: "Gracefully shutdown a VM",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				domain, err := libvirt.GetDomain(args[0])
				if err != nil {
					return err
				}
				return domain.Shutdown()
			},
		},
		&cobra.Command{
			Use:   "destroy [name|id]",
			Short: "Force stop and undefine a VM",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				domain, err := libvirt.GetDomain(args[0])
				if err != nil {
					return err
				}
				return domain.Destroy()
			},
		},
		&cobra.Command{
			Use:   "define [name]",
			Short: "Define a VM from XML",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				xmlFile, _ := cmd.Flags().GetString("xml")
				if xmlFile == "" {
					return fmt.Errorf("--xml flag is required")
				}
				data, err := os.ReadFile(xmlFile)
				if err != nil {
					return fmt.Errorf("reading XML: %w", err)
				}
				return libvirt.DefineDomain(args[0], string(data))
			},
		},
	)

	startCmd := cmd.Commands()[1]
	startCmd.Flags().Bool("force", false, "force stop the VM")
	stopCmd := cmd.Commands()[2]
	stopCmd.Flags().Bool("force", false, "force stop the VM")
	defineCmd := cmd.Commands()[5]
	defineCmd.Flags().String("xml", "", "path to XML definition file")

	return cmd
}

func newDiskCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "disk",
		Short: "Manage VM disks",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "create [path] [size]",
			Short: "Create a new disk image",
			Args:  cobra.ExactArgs(2),
			RunE: func(cmd *cobra.Command, args []string) error {
				format, _ := cmd.Flags().GetString("format")
				return kvm.CreateDisk(args[0], args[1], format)
			},
		},
		&cobra.Command{
			Use:   "resize [path] [size]",
			Short: "Resize a disk image",
			Args:  cobra.ExactArgs(2),
			RunE: func(cmd *cobra.Command, args []string) error {
				return kvm.ResizeDisk(args[0], args[1])
			},
		},
		&cobra.Command{
			Use:   "convert [source] [dest]",
			Short: "Convert disk image format",
			Args:  cobra.ExactArgs(2),
			RunE: func(cmd *cobra.Command, args []string) error {
				format, _ := cmd.Flags().GetString("format")
				return kvm.ConvertDisk(args[0], args[1], format)
			},
		},
		&cobra.Command{
			Use:   "info [path]",
			Short: "Get disk image info",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				info, err := kvm.DiskInfo(args[0])
				if err != nil {
					return err
				}
				fmt.Printf("Format: %s\nVirtual size: %s\nFile size: %s\n",
					info.Format, info.VirtualSize, info.FileSize)
				return nil
			},
		},
	)

	createCmd := cmd.Commands()[0]
	createCmd.Flags().String("format", "qcow2", "disk image format (qcow2, raw, vmdk)")
	convertCmd := cmd.Commands()[2]
	convertCmd.Flags().String("format", "qcow2", "target format")

	return cmd
}

func newNetCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "network",
		Short: "Manage virtual networks",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "list",
			Short: "List virtual networks",
			RunE: func(cmd *cobra.Command, args []string) error {
				networks, err := libvirt.ListNetworks()
				if err != nil {
					return err
				}
				fmt.Printf("%-20s %-15s %-20s\n", "NAME", "STATE", "BRIDGE")
				for _, n := range networks {
					fmt.Printf("%-20s %-15s %-20s\n", n.Name, n.State, n.Bridge)
				}
				return nil
			},
		},
		&cobra.Command{
			Use:   "start [name]",
			Short: "Start a virtual network",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				return libvirt.StartNetwork(args[0])
			},
		},
		&cobra.Command{
			Use:   "stop [name]",
			Short: "Stop a virtual network",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				return libvirt.StopNetwork(args[0])
			},
		},
		&cobra.Command{
			Use:   "delete [name]",
			Short: "Delete a virtual network",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				return libvirt.DeleteNetwork(args[0])
			},
		},
		&cobra.Command{
			Use:   "create [name]",
			Short: "Create a virtual network from XML",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				xmlFile, _ := cmd.Flags().GetString("xml")
				if xmlFile == "" {
					return fmt.Errorf("--xml flag is required")
				}
				data, err := os.ReadFile(xmlFile)
				if err != nil {
					return fmt.Errorf("reading XML: %w", err)
				}
				return libvirt.CreateNetwork(args[0], string(data))
			},
		},
	)

	createNetCmd := cmd.Commands()[4]
	createNetCmd.Flags().String("xml", "", "path to XML definition file")

	return cmd
}

func newSnapshotCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "snapshot",
		Short: "Manage VM snapshots",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "list [name|id]",
			Short: "List snapshots for a VM",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				domain, err := libvirt.GetDomain(args[0])
				if err != nil {
					return err
				}
				snaps, err := domain.ListSnapshots()
				if err != nil {
					return err
				}
				fmt.Printf("%-30s %-30s %-15s\n", "NAME", "CREATED", "STATE")
				for _, s := range snaps {
					fmt.Printf("%-30s %-30s %-15s\n", s.Name, s.Created, s.State)
				}
				return nil
			},
		},
		&cobra.Command{
			Use:   "create [name|id] [snapname]",
			Short: "Create a snapshot",
			Args:  cobra.ExactArgs(2),
			RunE: func(cmd *cobra.Command, args []string) error {
				desc, _ := cmd.Flags().GetString("description")
				domain, err := libvirt.GetDomain(args[0])
				if err != nil {
					return err
				}
				return domain.CreateSnapshot(args[1], desc)
			},
		},
		&cobra.Command{
			Use:   "revert [name|id] [snapname]",
			Short: "Revert to a snapshot",
			Args:  cobra.ExactArgs(2),
			RunE: func(cmd *cobra.Command, args []string) error {
				domain, err := libvirt.GetDomain(args[0])
				if err != nil {
					return err
				}
				return domain.RevertSnapshot(args[1])
			},
		},
		&cobra.Command{
			Use:   "delete [name|id] [snapname]",
			Short: "Delete a snapshot",
			Args:  cobra.ExactArgs(2),
			RunE: func(cmd *cobra.Command, args []string) error {
				domain, err := libvirt.GetDomain(args[0])
				if err != nil {
					return err
				}
				return domain.DeleteSnapshot(args[1])
			},
		},
	)

	createSnapCmd := cmd.Commands()[1]
	createSnapCmd.Flags().String("description", "", "snapshot description")

	return cmd
}

func newBackupCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "backup",
		Short: "Backup and restore VMs",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "export [name|id] [path]",
			Short: "Export VM to backup",
			Args:  cobra.ExactArgs(2),
			RunE: func(cmd *cobra.Command, args []string) error {
				format, _ := cmd.Flags().GetString("format")
				domain, err := libvirt.GetDomain(args[0])
				if err != nil {
					return err
				}
				return domain.Export(args[1], format)
			},
		},
	)

	exportCmd := cmd.Commands()[0]
	exportCmd.Flags().String("format", "qcow2", "backup format")

	return cmd
}

func newPassthroughCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "passthrough",
		Short: "Manage PCI/device passthrough",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "list",
			Short: "List available PCI devices",
			RunE: func(cmd *cobra.Command, args []string) error {
				output, err := kvm.ListPCIDevices()
				if err != nil {
					return err
				}
				fmt.Print(output)
				return nil
			},
		},
	)

	return cmd
}

func newCloudInitCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "cloudinit",
		Short: "Manage cloud-init images",
	}

	cmd.AddCommand(
		&cobra.Command{
			Use:   "create [path]",
			Short: "Create a cloud-init ISO",
			Args:  cobra.ExactArgs(1),
			RunE: func(cmd *cobra.Command, args []string) error {
				userData, _ := cmd.Flags().GetString("user-data")
				metaData, _ := cmd.Flags().GetString("meta-data")
				return kvm.CreateCloudInitISO(args[0], userData, metaData)
			},
		},
	)

	createCI := cmd.Commands()[0]
	createCI.Flags().String("user-data", "", "path to user-data file")
	createCI.Flags().String("meta-data", "", "path to meta-data file")

	return cmd
}

func newHealthCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "health",
		Short: "KVM health check",
		RunE: func(cmd *cobra.Command, args []string) error {
			domains, err := libvirt.ListDomains()
			if err != nil {
				return err
			}
			fmt.Printf("KVM Domains: %d\n", len(domains))
			for _, d := range domains {
				fmt.Printf("  %d %-30s %s\n", d.ID, d.Name, d.State)
			}
			networks, err := libvirt.ListNetworks()
			if err != nil {
				return err
			}
			fmt.Printf("Virtual Networks: %d\n", len(networks))
			for _, n := range networks {
				fmt.Printf("  %-20s %s\n", n.Name, n.State)
			}
			return nil
		},
	}
}
