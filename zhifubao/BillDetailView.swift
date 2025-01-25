import SwiftUI

struct BillDetailView: View {
    @State private var paymentTime = Date()
    @State private var receiverName = ""
    let amount = "-1,100.00"
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .center, spacing: 10) {
                        Text(amount)
                            .font(.system(size: 40, weight: .medium))
                            .padding(.vertical)
                        Text("交易成功")
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                
                Section {
                    HStack {
                        Text("支付时间")
                        Spacer()
                        Text(Self.dateFormatter.string(from: paymentTime))
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("付款方式")
                        Spacer()
                        Text("余额宝")
                            .foregroundColor(.gray)
                    }
                }
                
                Section {
                    HStack {
                        Text("商品说明")
                        Spacer()
                        Text("收钱码收款")
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("收款方全称")
                        TextField("请输入收款方名称", text: $receiverName)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section {
                    NavigationLink(destination: Text("账单分类")) {
                        Text("账单分类")
                        Spacer()
                        Text("生活服务")
                            .foregroundColor(.gray)
                    }
                    
                    Button(action: {
                        // 添加标签和备注的操作
                    }) {
                        HStack {
                            Text("标签和备注")
                            Spacer()
                            Image(systemName: "plus")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        // 联系收款方
                    }) {
                        Text("联系收款方")
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: {
                        // 查看往来记录
                    }) {
                        Text("查看往来记录")
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("账单详情")
        }
    }
}

#Preview {
    BillDetailView()
}