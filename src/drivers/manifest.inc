; Orden de inicializacion. Agrega aqui el descriptor de tu nuevo driver.
driver_manifest:
    dd vga_driver
    dd pit_driver
    dd ps2_driver
    dd mouse_driver
    dd pci_driver
    dd ata_driver
    dd rtc_driver
    dd loopback_driver
    dd serial_driver
; EXTRA_DRIVERS
    dd 0
